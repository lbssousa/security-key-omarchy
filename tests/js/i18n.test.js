const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const dir = path.join(__dirname, "../../i18n")
const load = file => JSON.parse(fs.readFileSync(path.join(dir, file), "utf8"))
const english = load("en.json")
const holes = text => (String(text).match(/%\d/g) || []).sort().join(",")

// Every language Omarchy offers under Setup > Language.
const omarchyLanguages = "/usr/share/omarchy/default/i18n/locales.json"

test("every catalog has exactly the English keys and placeholders", () => {
  for (const file of fs.readdirSync(dir).filter(f => f.endsWith(".json"))) {
    const catalog = load(file)
    assert.deepEqual(Object.keys(catalog).sort(), Object.keys(english).sort(), file)
    for (const key of Object.keys(english)) {
      assert.equal(typeof catalog[key], "string", `${file} ${key}`)
      assert.ok(catalog[key].length > 0, `${file} ${key}`)
      assert.equal(holes(catalog[key]), holes(english[key]), `${file} ${key}`)
    }
  }
})

test("a catalog for each Omarchy language", { skip: !fs.existsSync(omarchyLanguages) }, () => {
  const codes = Object.keys(JSON.parse(fs.readFileSync(omarchyLanguages, "utf8")))
  for (const code of codes) assert.ok(fs.existsSync(path.join(dir, code + ".json")), code)
})
