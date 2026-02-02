defmodule Piano.Domain do
  @moduledoc """
  Main Ash domain for Piano with AI/MCP capabilities.

  This domain exposes tools via the Model Context Protocol (MCP) for:
  - Browser automation (navigate, click, input, screenshot)
  - Web content extraction (fetch, clean, structured data)
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource Piano.Tools.BrowserAgentResource
    resource Piano.Tools.WebCleanerResource
    resource Piano.Tools.VoiceToolResource
    resource Piano.Tools.VisionToolResource
  end

  tools do
    # Browser tools
    tool(:browser_visit, Piano.Tools.BrowserAgentResource, :visit,
      description: "Navigate browser to a URL and extract content"
    )

    tool(:browser_click, Piano.Tools.BrowserAgentResource, :click,
      description: "Click an element on the current browser page"
    )

    tool(:browser_input, Piano.Tools.BrowserAgentResource, :input,
      description: "Input text into a form field"
    )

    tool(:browser_find, Piano.Tools.BrowserAgentResource, :find,
      description: "Find elements matching a CSS selector"
    )

    tool(:browser_screenshot, Piano.Tools.BrowserAgentResource, :screenshot,
      description: "Take a screenshot of the current page"
    )

    tool(:browser_get_content, Piano.Tools.BrowserAgentResource, :get_content,
      description: "Extract text content from the current page"
    )

    tool(:browser_current_url, Piano.Tools.BrowserAgentResource, :current_url,
      description: "Get the current page URL"
    )

    tool(:browser_execute_script, Piano.Tools.BrowserAgentResource, :execute_script,
      description: "Execute JavaScript in the browser"
    )

    # Web fetch tools
    tool(:web_fetch, Piano.Tools.WebCleanerResource, :fetch,
      description: "Fetch a webpage and extract clean, LLM-friendly content"
    )

    tool(:web_extract_text, Piano.Tools.WebCleanerResource, :extract_text,
      description: "Quickly extract text from a URL (optimized for LLM context)"
    )

    tool(:web_extract_markdown, Piano.Tools.WebCleanerResource, :extract_markdown,
      description: "Extract content as markdown from a URL"
    )

    tool(:web_extract_structured, Piano.Tools.WebCleanerResource, :extract_structured,
      description: "Extract structured content (title, headings, links, paragraphs)"
    )

    # Voice/ASR tools
    tool(:voice_transcribe, Piano.Tools.VoiceToolResource, :transcribe,
      description:
        "Transcribe audio or voice file to text using ASR. Use when user sends a voice message or audio file."
    )

    # Vision/Image tools
    tool(:vision_analyze, Piano.Tools.VisionToolResource, :analyze,
      description:
        "Analyze an image and answer a specific question about it. Use when user sends an image and asks something about it."
    )

    tool(:vision_describe, Piano.Tools.VisionToolResource, :describe,
      description:
        "Get a general description of an image. Use when user sends an image without specific question."
    )

    tool(:vision_extract_text, Piano.Tools.VisionToolResource, :extract_text,
      description: "Extract text/OCR from an image. Use when you need to read text from an image."
    )
  end
end
