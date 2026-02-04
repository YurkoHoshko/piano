defmodule Piano.Domain do
  @moduledoc """
  Main Ash domain for Piano with AI/MCP capabilities.

  This domain exposes tools via the Model Context Protocol (MCP) for:
  - Browser automation (navigate, click, input, screenshot)
  - Web content extraction (fetch, clean, structured data)

  ## Tool Output Format

  Content-heavy tools (browser_visit, browser_get_content, web_fetch, etc.) save
  their output to the filesystem to prevent context window overflow. They return:
  - `preview`: First ~100 characters of content (for quick scanning)
  - `path`: Full path to the saved file containing complete content
  - `size`: Total character count
  - `truncated`: Boolean indicating if preview was truncated

  To access the full content, use the `read` tool with the provided `path`.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource Piano.Tools.BrowserAgentResource
    resource Piano.Tools.WebCleanerResource
    resource Piano.Tools.VoiceToolResource
    resource Piano.Tools.VisionToolResource
    resource Piano.Tools.SurfaceToolResource
  end

  tools do
    # Browser tools
    tool(:browser_visit, Piano.Tools.BrowserAgentResource, :visit,
      description:
        "Navigate browser to a URL. Content is saved to file - returns preview and path. Use read tool on path to access full content."
    )

    tool(:browser_click, Piano.Tools.BrowserAgentResource, :click,
      description: "Click an element on the current browser page by CSS selector"
    )

    tool(:browser_input, Piano.Tools.BrowserAgentResource, :input,
      description: "Input text into a form field identified by CSS selector"
    )

    tool(:browser_find, Piano.Tools.BrowserAgentResource, :find,
      description:
        "Find elements matching a CSS selector. Results saved to file - returns preview and path."
    )

    tool(:browser_screenshot, Piano.Tools.BrowserAgentResource, :screenshot,
      description: "Take a screenshot of the current page. Returns path to saved image file."
    )

    tool(:browser_get_content, Piano.Tools.BrowserAgentResource, :get_content,
      description:
        "Extract text content from current page. Content saved to file - returns preview and path."
    )

    tool(:browser_current_url, Piano.Tools.BrowserAgentResource, :current_url,
      description: "Get the current page URL"
    )

    tool(:browser_execute_script, Piano.Tools.BrowserAgentResource, :execute_script,
      description: "Execute JavaScript in the browser. Large results saved to file."
    )

    # Web fetch tools
    tool(:web_fetch, Piano.Tools.WebCleanerResource, :fetch,
      description:
        "Fetch webpage and extract clean content. Output saved to file - returns preview and path. Use read tool on path for full content."
    )

    tool(:web_extract_text, Piano.Tools.WebCleanerResource, :extract_text,
      description:
        "Extract text from URL optimized for LLM context. Saved to file - returns preview and path."
    )

    tool(:web_extract_markdown, Piano.Tools.WebCleanerResource, :extract_markdown,
      description:
        "Extract content as markdown from URL. Saved to file - returns preview and path."
    )

    tool(:web_extract_structured, Piano.Tools.WebCleanerResource, :extract_structured,
      description:
        "Extract structured content (title, headings, links). Saved as JSON - returns preview and path."
    )

    # # Voice/ASR tools
    # tool(:voice_transcribe, Piano.Tools.VoiceToolResource, :transcribe,
    #   description:
    #     "Transcribe audio or voice file to text using ASR. Use when user sends a voice message or audio file."
    # )

    # # Vision/Image tools
    # tool(:vision_analyze, Piano.Tools.VisionToolResource, :analyze,
    #   description:
    #     "Analyze an image and answer a specific question about it. Use when user sends an image and asks something about it."
    # )

    # tool(:vision_describe, Piano.Tools.VisionToolResource, :describe,
    #   description:
    #     "Get a general description of an image. Use when user sends an image without specific question."
    # )

    # tool(:vision_extract_text, Piano.Tools.VisionToolResource, :extract_text,
    #   description: "Extract text/OCR from an image. Use when you need to read text from an image."
    # )

    # Surface messaging tools
    tool(:surface_send_message, Piano.Tools.SurfaceToolResource, :send_message,
      description:
        "Send a message to a surface (Telegram, etc.). Use for notifications or background task results."
    )

    tool(:telegram_send, Piano.Tools.SurfaceToolResource, :send_to_chat,
      description:
        "Send a message directly to a Telegram chat by chat_id. Supports markdown."
    )
  end
end
