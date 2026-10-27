import asyncio
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import stat
import tempfile
import unittest

HELPER = pathlib.Path(__file__).resolve().parents[2] / "key-helper"
loader = importlib.machinery.SourceFileLoader("key_helper", str(HELPER))
spec = importlib.util.spec_from_loader("key_helper", loader)
helper = importlib.util.module_from_spec(spec)
loader.exec_module(helper)

DEVICES = "/dev/hidraw1: vendor=0x1050, product=0x0407 (Yubico YubiKey OTP+FIDO+CCID)\n"
INFO = """proto: 0x02
version strings: U2F_V2, FIDO_2_0, FIDO_2_1_PRE
options: rk, up, noplat, clientPin, credentialMgmtPreview
pin retries: 8
"""
CARD = """Reader:1050:0407:X:0:AID:D2760001240100000006203732350000:openpgp-card:
vendor:0006:Yubico:
serial:20373235:
name:Ada:Lovelace:
url:https\\x3a//keys.example/ada.asc:
fpr:AAAABBBBCCCCDDDDEEEEFFFF0000111122223333:1E5A0912DCA511B6FF009497815B06463B9F3121::
"""
PUBLIC = """pub:u:255:22:B10712C404063D38:1767115511:::u:::scESC:::#:::23::0:
fpr:::::::::PRIMARY0000000000000000000000000000000000:
"""
CRED1 = "HANDLEONE111,pubkey1,es256,+presence"
CRED2 = "HANDLETWO222,pubkey2,es256,+presence"


class FakeRunner:
    """Answers from a table keyed by the program's first two words; records every run."""

    def __init__(self):
        self.calls = []
        self.answers = {
            ("fido2-token", "-L"): helper.Result(0, DEVICES),
            ("fido2-token", "-I"): helper.Result(0, INFO),
            ("gpg", "--card-status"): helper.Result(0, CARD),
            ("gpg", "--list-keys"): helper.Result(0, PUBLIC),
            ("gpg", "--list-secret-keys"): helper.Result(0, "sec:u:255\n"),
        }
        self.cancelled = False
        self.hook = None

    async def run(self, args, stdin=None, env=None, cwd=None, timeout=None):
        self.calls.append((list(args), stdin, env, cwd))
        if self.hook:
            result = await self.hook(args, stdin, env, cwd)
            if result is not None:
                return result
        return self.answers.get(tuple(args[:2]), helper.Result(0))

    def cancel(self):
        self.cancelled = True

    def ran(self, *prefix):
        return [c for c in self.calls if tuple(c[0][:len(prefix)]) == prefix]


class SessionTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.tmp.name)
        self.home = root / "home"
        self.pam = root / "pam.d"
        self.home.mkdir()
        self.pam.mkdir()
        (self.pam / "sudo").write_text("auth sufficient pam_u2f.so cue\nauth include system-auth\n")
        (self.pam / "polkit-1").write_text("auth include system-auth\n")
        self.paths = helper.Paths(home=str(self.home), config=str(self.home / ".config"),
                                  pam_dirs=[str(self.pam)], runtime=str(root))
        self.runner = FakeRunner()
        self.events = []
        self.session = helper.Session(self.runner, self.events.append, self.paths, "ada", "/askpass")

    def tearDown(self):
        self.tmp.cleanup()

    def run_op(self, coroutine):
        asyncio.run(coroutine)

    def last(self, kind):
        return [e for e in self.events if e["type"] == kind][-1]

    def authfile(self):
        return pathlib.Path(self.paths.authfile)

    # -- parsers ---------------------------------------------------------

    def test_parse_devices_and_info(self):
        self.assertEqual(helper.parse_devices(DEVICES + "garbage\n"),
                         [{"path": "/dev/hidraw1", "name": "Yubico YubiKey OTP+FIDO+CCID"}])
        self.assertEqual(helper.parse_info(INFO), {"rk": True, "clientPin": True, "pinRetries": 8})
        no_pin = helper.parse_info("options: up, noclientPin\n")
        self.assertEqual((no_pin["rk"], no_pin["clientPin"], no_pin["pinRetries"]), (False, False, -1))

    def test_parse_card(self):
        card = helper.parse_card(CARD)
        self.assertEqual(card["holder"], "Ada Lovelace")
        self.assertEqual(card["url"], "https://keys.example/ada.asc")
        self.assertEqual(card["fingerprints"], ["AAAABBBBCCCCDDDDEEEEFFFF0000111122223333",
                                                "1E5A0912DCA511B6FF009497815B06463B9F3121"])
        self.assertIsNone(helper.parse_card("Reader:1050:0407:X:0:AID:piv-only:\n"))
        self.assertIsNone(helper.parse_card(""))

    def test_pam_lines(self):
        self.assertEqual(helper.pam_u2f("auth sufficient pam_u2f.so cue authfile=/etc/fido2/fido2\n"),
                         {"u2f": True, "authfile": "/etc/fido2/fido2"})
        self.assertEqual(helper.pam_u2f("#auth sufficient pam_u2f.so\nauth include system-auth\n"),
                         {"u2f": False, "authfile": ""})

    def test_merge_skips_known_key_handles(self):
        self.assertEqual(helper.merge_credentials([CRED1], ["HANDLEONE111,other,es256,+presence", CRED2]),
                         [CRED1, CRED2])

    def test_errors_map_to_codes(self):
        self.assertEqual(helper.fido_error("error: fido_dev_make_cred (49) FIDO_ERR_PIN_INVALID"), "pin-invalid")
        self.assertEqual(helper.fido_error("error: fido_dev_make_cred (50) FIDO_ERR_PIN_BLOCKED"), "pin-blocked")
        self.assertEqual(helper.fido_error("error: fido_dev_make_cred (47) FIDO_ERR_ACTION_TIMEOUT"), "timeout")
        self.assertEqual(helper.fido_error("Unable to load resident keys: PIN incorrect"), "pin-invalid")
        self.assertEqual(helper.fido_error("No keys to download"), "ssh-none")
        self.assertEqual(helper.fido_error("something odd"), "generic")
        empty = "Enter PIN for /dev/hidraw1: error: fido_dev_make_cred (-7) FIDO_ERR_INVALID_ARGUMENT"
        self.assertEqual(helper.fido_error(empty), "pin-required")
        self.assertEqual(helper.fido_error(empty, "1234"), "generic")

    # -- state -----------------------------------------------------------

    def test_refresh_reports_everything(self):
        self.authfile().parent.mkdir(parents=True)
        self.authfile().write_text("bob:BOBKEY,p,es256,+presence\nada:%s\n" % CRED1)
        (self.home / ".ssh").mkdir()
        (self.home / ".ssh" / "id_ed25519_sk_rk").write_text("k")
        (self.home / ".ssh" / "id_ed25519_sk_rk.pub").write_text("k")
        self.run_op(self.session.refresh())
        state = self.last("state")
        self.assertEqual(state["devices"][0]["name"], "Yubico YubiKey OTP+FIDO+CCID")
        self.assertTrue(state["devices"][0]["rk"])
        self.assertEqual(state["credentials"], [{"handle": "HANDLEONE111", "label": "HANDLEONE1"}])
        self.assertEqual(state["pam"]["sudo"], {"u2f": True, "authfile": ""})
        self.assertFalse(state["pam"]["polkit"]["u2f"])
        self.assertEqual(state["card"]["serial"], "20373235")
        self.assertEqual((state["keyState"], state["trusted"]), ("ready", True))
        self.assertEqual(state["sshKeys"], ["id_ed25519_sk_rk"])
        self.assertEqual(state["sharedCount"], 0)

    def test_key_states(self):
        self.runner.answers[("gpg", "--list-secret-keys")] = helper.Result(2, "")
        self.run_op(self.session.refresh())
        self.assertEqual(self.last("state")["keyState"], "public")
        self.runner.answers[("gpg", "--list-keys")] = helper.Result(2, "")
        self.run_op(self.session.refresh())
        self.assertEqual(self.last("state")["keyState"], "missing")
        self.runner.answers[("gpg", "--card-status")] = helper.Result(2, "")
        self.run_op(self.session.refresh())
        self.assertIsNone(self.last("state")["card"])
        self.assertEqual(self.last("state")["keyState"], "none")

    def test_shared_authfile_is_counted(self):
        shared = pathlib.Path(self.tmp.name) / "fido2"
        shared.write_text("ada:%s:%s\nbob:X,y,es256,+presence\n" % (CRED1, CRED2))
        (self.pam / "sudo").write_text("auth sufficient pam_u2f.so cue authfile=%s\n" % shared)
        self.run_op(self.session.refresh())
        self.assertEqual(self.last("state")["sharedCount"], 2)

    def test_poll_refreshes_only_when_keys_change(self):
        self.run_op(self.session.refresh())
        self.events.clear()
        self.run_op(self.session.poll())
        self.assertEqual(self.events, [])
        self.runner.answers[("fido2-token", "-L")] = helper.Result(0, "")
        self.run_op(self.session.poll())
        self.assertEqual(self.last("state")["devices"], [])

    # -- FIDO2 -----------------------------------------------------------

    def registered(self):
        self.run_op(self.session.refresh())
        self.events.clear()

    def test_register_writes_a_private_authfile(self):
        self.registered()
        self.runner.answers[("pamu2fcfg", "-u")] = helper.Result(0, "ada:%s\n" % CRED1)
        self.run_op(self.session.fido_register("1234"))
        args, stdin, _, _ = self.runner.ran("pamu2fcfg")[0]
        self.assertEqual((args, stdin), (["pamu2fcfg", "-u", "ada"], "1234\n"))
        self.assertEqual(self.events[0], {"type": "busy", "op": "fido.register", "stage": "touch"})
        self.assertEqual(self.last("done")["op"], "fido.register")
        self.assertEqual(self.authfile().read_text(), "ada:%s\n" % CRED1)
        self.assertEqual(stat.S_IMODE(self.authfile().stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.authfile().parent.stat().st_mode), 0o700)

    def test_register_appends_and_keeps_other_users(self):
        self.authfile().parent.mkdir(parents=True)
        self.authfile().write_text("bob:B,p,es256,+presence\nada:%s\n" % CRED1)
        self.registered()
        self.runner.answers[("pamu2fcfg", "-u")] = helper.Result(0, "ada:%s\n" % CRED2)
        self.run_op(self.session.fido_register(""))
        self.assertIsNone(self.runner.ran("pamu2fcfg")[0][1])
        self.assertEqual(self.authfile().read_text(), "bob:B,p,es256,+presence\nada:%s:%s\n" % (CRED1, CRED2))
        self.assertEqual(len(self.last("state")["credentials"]), 2)

    def test_register_failure_reports_the_code(self):
        self.registered()
        self.runner.answers[("pamu2fcfg", "-u")] = helper.Result(1, "", "error: fido_dev_make_cred (49) FIDO_ERR_PIN_INVALID\n")
        self.run_op(self.session.fido_register("0000"))
        self.assertEqual(self.last("error")["code"], "pin-invalid")
        self.assertFalse(self.authfile().exists())

    def test_register_needs_a_key(self):
        self.runner.answers[("fido2-token", "-L")] = helper.Result(0, "")
        self.registered()
        self.run_op(self.session.fido_register(""))
        self.assertEqual(self.last("error")["code"], "no-device")
        self.assertEqual(self.runner.ran("pamu2fcfg"), [])

    def test_remove_drops_one_key_then_the_line(self):
        self.authfile().parent.mkdir(parents=True)
        self.authfile().write_text("ada:%s:%s\nbob:B,p,es256,+presence\n" % (CRED1, CRED2))
        self.registered()
        self.run_op(self.session.fido_remove(0))
        self.assertEqual(self.authfile().read_text(), "bob:B,p,es256,+presence\nada:%s\n" % CRED2)
        self.run_op(self.session.fido_remove(0))
        self.assertEqual(self.authfile().read_text(), "bob:B,p,es256,+presence\n")
        self.run_op(self.session.fido_remove(5))
        self.assertEqual(self.last("error")["code"], "generic")

    # -- OpenPGP ---------------------------------------------------------

    def test_gpg_import_tries_the_card_url_then_the_keyservers(self):
        self.registered()
        self.runner.answers[("gpg", "--fetch-keys")] = helper.Result(2, "", "no data")
        self.run_op(self.session.gpg_import())
        self.assertEqual(self.runner.ran("gpg", "--fetch-keys")[0][0][2], "https://keys.example/ada.asc")
        self.assertEqual(self.runner.ran("gpg", "--recv-keys")[0][0][2], "AAAABBBBCCCCDDDDEEEEFFFF0000111122223333")
        self.assertEqual(self.last("done")["op"], "gpg.import")
        self.runner.answers[("gpg", "--recv-keys")] = helper.Result(2, "", "no data")
        self.run_op(self.session.gpg_import())
        self.assertEqual(self.last("error")["code"], "import-failed")

    def test_gpg_trust_uses_the_primary_fingerprint(self):
        self.registered()
        self.run_op(self.session.gpg_trust())
        _, stdin, _, _ = self.runner.ran("gpg", "--import-ownertrust")[0]
        self.assertEqual(stdin, "PRIMARY0000000000000000000000000000000000:6:\n")
        self.assertEqual(self.last("done")["op"], "gpg.trust")

    def test_gpg_remove_takes_out_the_public_key_and_the_card_stubs(self):
        self.registered()
        self.runner.answers[("gpg", "--list-secret-keys")] = helper.Result(
            0, "sec:u:255:22:B10712C404063D38::::::::::D2760001240100000006203732350000:\n"
               "ssb:u:255:18:815B06463B9F3121::::::::::#:\n")
        self.run_op(self.session.gpg_remove())
        args = self.runner.ran("gpg", "--batch")[0][0]
        self.assertEqual(args, ["gpg", "--batch", "--yes", "--delete-secret-and-public-keys",
                                "PRIMARY0000000000000000000000000000000000"])
        self.assertEqual(self.last("done")["op"], "gpg.remove")

    def test_gpg_remove_never_touches_a_secret_kept_on_disk(self):
        self.registered()
        for listing in ("sec:u:255:22:B10712C404063D38::::::::::+:\n", "sec:u:255\n"):
            self.events.clear()
            self.runner.answers[("gpg", "--list-secret-keys")] = helper.Result(0, listing)
            self.run_op(self.session.gpg_remove())
            self.assertEqual(self.last("error")["code"], "secret-on-disk")
        self.assertEqual(self.runner.ran("gpg", "--batch"), [])

    def test_gpg_remove_without_secret_stubs_deletes_the_public_key(self):
        self.registered()
        self.runner.answers[("gpg", "--list-secret-keys")] = helper.Result(2, "")
        self.run_op(self.session.gpg_remove())
        self.assertEqual(self.runner.ran("gpg", "--batch")[0][0][3], "--delete-keys")

    # -- SSH -------------------------------------------------------------

    def test_ssh_remove_deletes_the_pair_and_only_listed_keys(self):
        ssh = self.home / ".ssh"
        ssh.mkdir()
        for name in ("id_ed25519_sk_rk_x", "id_ed25519_sk_rk_x.pub", "id_ed25519", "id_ed25519.pub"):
            (ssh / name).write_text("k")
        self.registered()
        self.run_op(self.session.ssh_remove("id_ed25519_sk_rk_x"))
        self.assertEqual(self.last("done"), {"type": "done", "op": "ssh.remove", "name": "id_ed25519_sk_rk_x"})
        for name in ("id_ed25519", "../.ssh/id_ed25519", "id_ed25519_sk_rk_x"):
            self.events.clear()
            self.run_op(self.session.ssh_remove(name))
            self.assertEqual(self.last("error")["code"], "remove-failed")
        self.assertEqual(sorted(os.listdir(ssh)), ["id_ed25519", "id_ed25519.pub"])


    def test_ssh_import_hands_the_pin_to_askpass_and_never_overwrites(self):
        (self.home / ".ssh").mkdir()
        (self.home / ".ssh" / "id_ed25519_sk_rk_old").write_text("mine")
        self.registered()
        seen = {}

        async def keygen(args, stdin, env, cwd):
            if args[0] != "ssh-keygen":
                return None
            seen["env"] = env
            seen["args"] = args
            # What our own askpass would do: ask the helper over its socket.
            reader, writer = await asyncio.open_unix_connection(env[helper.ASKPASS_ENV])
            writer.write(b"Enter PIN for authenticator: \n")
            await writer.drain()
            seen["pin"] = (await reader.readline()).decode().strip()
            writer.close()
            for name in ("id_ed25519_sk_rk", "id_ed25519_sk_rk_old"):
                pathlib.Path(cwd, name).write_text("key")
                pathlib.Path(cwd, name + ".pub").write_text("pub")
            return helper.Result(0)

        self.runner.hook = keygen
        self.run_op(self.session.ssh_import("4321"))
        self.assertEqual(seen["pin"], "4321")
        self.assertEqual(seen["args"], ["ssh-keygen", "-K", "-N", ""])
        self.assertEqual((seen["env"]["SSH_ASKPASS"], seen["env"]["SSH_ASKPASS_REQUIRE"]), ("/askpass", "force"))
        self.assertNotIn("4321", json.dumps(seen["env"]))
        done = self.last("done")
        self.assertEqual((done["imported"], done["skipped"]), (["id_ed25519_sk_rk"], ["id_ed25519_sk_rk_old"]))
        ssh = self.home / ".ssh"
        self.assertEqual((ssh / "id_ed25519_sk_rk_old").read_text(), "mine")
        self.assertEqual(stat.S_IMODE((ssh / "id_ed25519_sk_rk").stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE((ssh / "id_ed25519_sk_rk.pub").stat().st_mode), 0o644)
        # The private work folder is gone.
        self.assertEqual([n for n in os.listdir(self.tmp.name) if n.startswith("security-key-")], [])

    def test_askpass_mode_prints_the_pin_once(self):
        async def scenario():
            path = os.path.join(self.tmp.name, "askpass")
            server = await helper.serve_pin(path, "2468")
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode) & 0o077, 0)
            env = dict(os.environ, **{helper.ASKPASS_ENV: path})
            outputs = []
            for _ in range(2):
                # As ssh-keygen runs it: the program, then the prompt alone.
                proc = await asyncio.create_subprocess_exec(
                    str(HELPER), "Enter PIN for authenticator: ",
                    env=env, stdin=asyncio.subprocess.DEVNULL, stdout=asyncio.subprocess.PIPE)
                out, _ = await proc.communicate()
                outputs.append((proc.returncode, out.decode()))
            server.close()
            return outputs

        self.assertEqual(asyncio.run(scenario()), [(0, "2468\n"), (1, "")])

    def test_ssh_import_failure(self):
        self.registered()
        self.runner.answers[("ssh-keygen", "-K")] = helper.Result(255, "", "Unable to load resident keys: PIN incorrect")
        self.run_op(self.session.ssh_import("0000"))
        self.assertEqual(self.last("error")["code"], "pin-invalid")

    # -- commands --------------------------------------------------------

    def test_one_operation_at_a_time_and_cancel(self):
        async def scenario():
            started = asyncio.Event()

            async def slow(args, stdin, env, cwd):
                if args[0] == "pamu2fcfg":
                    started.set()
                    await asyncio.sleep(10)
                return None

            self.runner.hook = slow
            self.session.handle_line(json.dumps({"cmd": "fido.register", "pin": "1"}))
            await started.wait()
            self.assertFalse(self.session.start("refresh", self.session.refresh()))
            self.session.handle_line('{"cmd":"cancel"}')
            await asyncio.sleep(0)
            await asyncio.sleep(0)
            self.assertTrue(self.runner.cancelled)
            self.assertIsNone(self.session.op)

        self.session.devices = [{"path": "/dev/hidraw1"}]
        asyncio.run(scenario())
        self.assertEqual(self.last("cancelled")["op"], "fido.register")

    def test_a_command_waits_for_a_running_refresh(self):
        async def scenario():
            release = asyncio.Event()

            async def slow_list(args, stdin, env, cwd):
                if args[:2] == ["fido2-token", "-L"] and not release.is_set():
                    await release.wait()
                return None

            self.runner.hook = slow_list
            self.session.start("refresh", self.session.poll())
            await asyncio.sleep(0)
            self.session.handle_line('{"cmd":"gpg.trust"}')
            self.assertEqual(self.session.op, "refresh")
            release.set()
            for _ in range(20):
                await asyncio.sleep(0)
            while self.session.task is not None:
                await self.session.task

        self.session.devices = [{"path": "/dev/hidraw1"}]
        self.session.card = helper.parse_card(CARD)
        asyncio.run(scenario())
        self.assertEqual(self.last("done")["op"], "gpg.trust")

    def test_invalid_input_is_ignored(self):
        self.session.handle_line("not json")
        self.session.handle_line("[1]")
        self.session.handle_line('{"cmd":"fido.remove","index":"x"}')
        self.assertIsNone(self.session.op)


if __name__ == "__main__":
    unittest.main()
