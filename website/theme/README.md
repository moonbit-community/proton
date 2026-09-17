# Syntax highlighting

This directory overrides only mdBook's `highlight.js`. Both books share it;
all other theme assets remain mdBook defaults. No npm install is needed.

`highlight.js` concatenates these unmodified upstream browser distributions,
separated by a semicolon:

1. Highlight.js 11.11.1 (BSD-3-Clause):
   https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.11.1/highlight.min.js
2. highlightjs-moonbit at commit `194acd8c9f964ce56623b31c5824fce01876be1f` (MIT):
   https://raw.githubusercontent.com/Kaida-Amethyst/highlightjs-moonbit/194acd8c9f964ce56623b31c5824fce01876be1f/dist/moonbit.min.js

The language module registers itself before mdBook's `book.js` highlights the
page. mdBook 0.4.52's bundled Highlight.js 10.1.1 cannot register this module,
so the override also supplies the compatible upstream highlighter.

Keep the license files and these source versions with future updates. Use
`moonbit` on Markdown code fences. No custom language grammar is maintained here.
