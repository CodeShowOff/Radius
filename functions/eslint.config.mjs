import js from "@eslint/js";
import tseslint from "@typescript-eslint/eslint-plugin";
import tsparser from "@typescript-eslint/parser";

export default [
  js.configs.recommended,
  {
    files: ["**/*.ts"],
    languageOptions: {
      parser: tsparser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module",
      },
    },
    plugins: {
      "@typescript-eslint": tseslint,
    },
    rules: {
      "quotes": ["error", "double"],
      "indent": ["error", 2],
      "max-len": ["error", {"code": 100}],
      "@typescript-eslint/no-explicit-any": "warn",
    },
  },
  {
    ignores: ["lib/**", "node_modules/**"],
  },
];
