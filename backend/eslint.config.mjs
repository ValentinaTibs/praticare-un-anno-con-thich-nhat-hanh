import js from '@eslint/js';
import tseslint from 'typescript-eslint';

export default tseslint.config(
  { ignores: ['dist/', 'coverage/', 'node_modules/'] },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ['**/*.ts'],
    languageOptions: {
      parserOptions: { projectService: true, tsconfigRootDir: import.meta.dirname },
    },
    rules: {
      // A promise nobody awaits loses its errors: in jobs and routes that means a silent failure.
      '@typescript-eslint/no-floating-promises': 'error',
      // Fastify runs async hooks such as `preHandler: authenticate`, but its types don't say so.
      '@typescript-eslint/no-misused-promises': ['error', { checksVoidReturn: { properties: false } }],
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
    },
  },
);
