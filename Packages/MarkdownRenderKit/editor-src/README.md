# mdedit editor bundle

`editor.js` is the CodeMirror 6 entry point that mdedit's editor pane loads (`Resources/editor.html`). It is bundled into one minified file, `../Sources/MarkdownRenderKit/Resources/codemirror-editor.min.js`, which is committed, so building the apps never needs Node.

To rebuild after changing `editor.js` or bumping a pinned version in `package.json`:

```sh
cd Packages/MarkdownRenderKit/editor-src
npm ci        # or `npm install` after editing package.json
npm run build
```

Commit `editor.js`, `package.json`, `package-lock.json` and the rebuilt bundle together.
