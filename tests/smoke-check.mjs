import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();

function read(relPath) {
  return fs.readFileSync(path.join(root, relPath), 'utf8');
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

const shiftTracker = read('shift-tracker/index.html');
const shiftSw = read('shift-tracker/sw.js');
const platform = read('index.html');
const holidayRequest = read('holiday-request/index.html');
const creditHours = read('credit-hours/index.html');
const kilnLog = read('kiln-log/index.html');
const userManagement = read('user-management/index.html');
const userManagementSql = read('docs/sql/user-management-admin.sql');
const sharedSuite = read('shared-suite.js');

assert(sharedSuite.includes('loadPwAppAccessState'), 'shared-suite.js should expose shared access loading.');
assert(sharedSuite.includes('licence'), 'shared-suite.js should expose shared licence helpers.');
assert(sharedSuite.includes('getPresetMap'), 'shared-suite.js should expose shared palette presets.');
assert(sharedSuite.includes('getPresetVarsMap'), 'shared-suite.js should expose shared palette variable maps.');

assert(shiftTracker.includes('requiresProfile: true'), 'Shift Tracker should require a platform profile.');
assert(shiftTracker.includes("suiteShared.supabase.createClient"), 'Shift Tracker should use the shared Supabase client wrapper.');
assert(shiftTracker.includes("navigator.serviceWorker.register('./sw.js'"), 'Shift Tracker should register its service worker.');
assert(shiftTracker.includes('shift_tracker_data_uid_'), 'Shift Tracker should use per-user synced tracker data keys.');
assert(shiftTracker.includes('const selectedDate=addDays(TODAY,S.viewOffset||0);'), 'Shift Tracker should derive the header date from the selected view date.');
assert(shiftTracker.includes('status(sh,selectedDate)'), 'Shift Tracker header cards should use the selected date.');
assert(shiftTracker.includes('renderShiftSummaryCard(active,selectedDate)'), 'Shift Tracker summary card should use the selected date.');
assert(shiftTracker.includes('const TOTAL_WORKED_SHIFTS=CYCLE.filter'), 'Shift Tracker should expose the total number of worked shifts in the cycle.');
assert(shiftTracker.includes('formatCycleCompletion(sh,selectedDate)'), 'Shift Tracker header cards should show cycle completion for the selected date.');
assert(fs.existsSync(path.join(root, 'shift-tracker', 'manifest.webmanifest')), 'Shift Tracker manifest should exist.');
assert(fs.existsSync(path.join(root, 'shift-tracker', 'icon.svg')), 'Shift Tracker icon should exist.');
assert(shiftSw.includes("caches.open(CACHE_NAME)"), 'Shift Tracker service worker should cache an app shell.');
assert(shiftTracker.includes('sharedPalette.getPresetMap'), 'Shift Tracker should use shared palette presets.');
assert(platform.includes('shared-suite.js'), 'Platform should load shared suite helpers.');
assert(platform.includes('sharedPalette.getPresetMap'), 'Platform should use shared palette presets.');

assert(holidayRequest.includes('suiteShared.licence.check'), 'Holiday Requests should use the shared licence helper.');
assert(holidayRequest.includes('suiteShared.access.loadPwAppAccessState'), 'Holiday Requests should use the shared access helper.');
assert(holidayRequest.includes('suiteShared.supabase.createClient'), 'Holiday Requests should use the shared Supabase client wrapper.');
assert(holidayRequest.includes('sharedPalette.getPresetVarsMap'), 'Holiday Requests should use shared palette presets.');

assert(creditHours.includes('suiteShared.licence.check'), 'Credit Hours should use the shared licence helper.');
assert(creditHours.includes('suiteShared.access.loadPwAppAccessState'), 'Credit Hours should use the shared access helper.');
assert(creditHours.includes('suiteShared.supabase.createClient'), 'Credit Hours should use the shared Supabase client wrapper.');
assert(creditHours.includes('sharedPalette.getPresetVarsMap'), 'Credit Hours should use shared palette presets.');

assert(kilnLog.includes('suiteShared.licence.check'), 'Kiln Log should use the shared licence helper.');
assert(kilnLog.includes('failOpen: false'), 'Kiln Log licence check should fail closed.');
assert(kilnLog.includes('suiteShared.supabase.createClient'), 'Kiln Log should use the shared Supabase client wrapper.');
assert(kilnLog.includes('sharedPalette.getPresetMap'), 'Kiln Log should use shared palette presets.');

assert(userManagement.includes('suiteShared.licence.check'), 'User Management should use the shared licence helper.');
assert(userManagement.includes('suiteShared.access.loadPwAppAccessState'), 'User Management should use the shared access helper.');
assert(userManagement.includes("sb.rpc('pw_is_admin_user')"), 'User Management should verify admin access server-side.');
assert(userManagement.includes("sb.rpc('pw_admin_user_management_snapshot')"), 'User Management should load users through admin RPC snapshot.');
assert(userManagement.includes("sb.rpc('pw_admin_user_management_update_user'"), 'User Management should save updates through admin RPC.');
assert(userManagementSql.includes('create or replace function public.pw_is_admin_user()'), 'User Management SQL should expose a no-arg admin check.');
assert(userManagement.includes('sharedPalette.getPresetVarsMap'), 'User Management should use shared palette presets.');

console.log('Smoke checks passed.');
