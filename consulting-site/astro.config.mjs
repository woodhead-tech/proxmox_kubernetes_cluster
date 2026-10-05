import { defineConfig } from 'astro/config';

export default defineConfig({
  output: 'static',
  // Astro 7 defaults to 'jsx' whitespace stripping; pin the Astro 6 behaviour so rendered output is unchanged.
  compressHTML: true,
  site: 'https://woodhead.tech',
});
