const fs = require('node:fs');
const path = require('node:path');
const tests = new Map();
const results = new Map();
for (const line of fs.readFileSync(path.join(__dirname, 'flutter-fixes.jsonl'), 'utf8').split(/\r?\n/)) {
  let event;
  try {event = JSON.parse(line);} catch {continue;}
  if (event.type === 'testStart') tests.set(event.test.id, event.test);
  if (event.type === 'testDone' && !event.hidden) results.set(event.testID, event.result);
}
const flutter = [...results].map(([id, result]) => ({name: tests.get(id)?.name, result}));
const summary = {flutter: {
  total: flutter.length,
  passed: flutter.filter(t => t.result === 'success').length,
  failed: flutter.filter(t => t.result !== 'success'),
  tests: flutter,
}};
for (const [key, file] of [['emulator', 'emulator-fixes.log'], ['functions', 'function-fixes.log'], ['households', 'household-fixes.log']]) {
  const log = fs.readFileSync(path.join(__dirname, file), 'utf8');
  summary[key] = Object.fromEntries(['tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'].map(name => {
    const match = log.match(new RegExp(`(?:ℹ|#) ${name} (\\d+)`));
    if (!match) throw new Error(`Missing ${name} summary in ${file}; the suite may not have finished.`);
    return [name, Number(match[1])];
  }));
}
summary.total = {tests: summary.flutter.total, passed: summary.flutter.passed, failed: summary.flutter.failed.length};
for (const key of ['emulator', 'functions', 'households']) {
  summary.total.tests += summary[key].tests;
  summary.total.passed += summary[key].pass;
  summary.total.failed += summary[key].fail;
}
fs.writeFileSync(path.join(__dirname, 'test-summary.json'), JSON.stringify(summary, null, 2));
console.log(JSON.stringify({flutter: {total: summary.flutter.total, passed: summary.flutter.passed, failed: summary.flutter.failed},
  emulator: summary.emulator, functions: summary.functions, households: summary.households, total: summary.total}, null, 2));
