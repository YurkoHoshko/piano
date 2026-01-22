---
name: web
description: Use when need to check out website / fill in a form / etc.
---

# web - shell command for simple LLM web browsing
shell-based web browser for LLMs that converts web pages to markdown, executes js, and interacts with pages.

# Convert a webpage to markdown
bin/web https://example.com

# Take a screenshot while scraping
bin/web https://example.com --screenshot page.png

# Execute JavaScript and capture log output along with markdown content
bin/web https://example.com --js "console.log(document.title)"

# Fill and submit a form
bin/web https://login.example.com \
    --form "login_form" \
    --input "username" --value "myuser" \
    --input "password" --value "mypass"

# Basic scraping
bin/web https://example.com

# Output raw HTML
bin/web https://example.com --raw > output.html

# With truncation and screenshot
web example.com --screenshot screenshot.png --truncate-after 123

# Form submission with Phoenix LiveView support
bin/web http://localhost:4000/users/log-in \
    --form "login_form" \
    --input "user[email]" --value "foo@bar" \
    --input "user[password]" --value "secret" \
    --after-submit "http://localhost:4000/authd/page"

# Execute JavaScript on the page
web example.com --js "document.querySelector('button').click()"

# Use named session profile
./web --profile "mysite" https://authenticated-site.com

Options
Usage: web <url> [options]

Options:
  --help                     Show this help message
  --raw                      Output raw page instead of converting to markdown
  --truncate-after <number>  Truncate output after <number> characters and append a notice (default: 100000)
  --screenshot <filepath>    Take a screenshot of the page and save it to the given filepath
  --form <id>                The id of the form for inputs
  --input <name>             Specify the name attribute for a form input field
  --value <value>            Provide the value to fill for the last --input field
  --after-submit <url>       After form submission and navigation, load this URL before converting to markdown
  --js <code>                Execute JavaScript code on the page after it loads
  --profile <name>           Use or create named session profile (default: "default")
