// Legacy Grunt plugins (campus client) still call util.isRegExp and friends,
// which Node.js removed in v23. Re-add the tiny predicates so the pinned build
// toolchain keeps working on current LTS/current Node releases.
const util = require('util');

if (typeof util.isRegExp !== 'function') util.isRegExp = (v) => v instanceof RegExp;
if (typeof util.isArray !== 'function') util.isArray = Array.isArray;
if (typeof util.isDate !== 'function') util.isDate = (v) => v instanceof Date;
if (typeof util.isError !== 'function') util.isError = (v) => v instanceof Error;
if (typeof util.isFunction !== 'function') util.isFunction = (v) => typeof v === 'function';
if (typeof util.isNull !== 'function') util.isNull = (v) => v === null;
if (typeof util.isNullOrUndefined !== 'function') util.isNullOrUndefined = (v) => v == null;
if (typeof util.isNumber !== 'function') util.isNumber = (v) => typeof v === 'number';
if (typeof util.isObject !== 'function') util.isObject = (v) => v !== null && typeof v === 'object';
if (typeof util.isPrimitive !== 'function') util.isPrimitive = (v) => v === null || (typeof v !== 'object' && typeof v !== 'function');
if (typeof util.isString !== 'function') util.isString = (v) => typeof v === 'string';
if (typeof util.isSymbol !== 'function') util.isSymbol = (v) => typeof v === 'symbol';
if (typeof util.isUndefined !== 'function') util.isUndefined = (v) => v === undefined;
