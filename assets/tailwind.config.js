const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = {
  content: [
    "./js/**/*.js",
    "../lib/piano_web.ex",
    "../lib/piano_web/**/*.*ex"
  ],
  theme: {
    extend: {
      colors: {
        brand: "#00d9ff",
      }
    },
  },
  plugins: []
}
