const js = require("@eslint/js");

module.exports = [
{
ignores: [
"node_modules/**",
"coverage/**",
"infra/terraform/.terraform/**",
],
},
js.configs.recommended,
{
files: ["**/*.js"],
languageOptions: {
ecmaVersion: "latest",
sourceType: "commonjs",
globals: {
console: "readonly",
process: "readonly",
module: "readonly",
require: "readonly",
__dirname: "readonly",
__filename: "readonly",
exports: "readonly",
Buffer: "readonly",
setTimeout: "readonly",
clearTimeout: "readonly",
},
},
rules: {
"no-unused-vars": ["error", {
argsIgnorePattern: "^_",
}],
"no-undef": "error",
"no-console": "off",
},
},
];