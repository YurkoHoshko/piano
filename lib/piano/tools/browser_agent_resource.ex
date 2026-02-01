defmodule Piano.Tools.BrowserAgentResource do
  @moduledoc """
  Ash resource wrapper for BrowserAgent tool calls via MCP.

  This resource wraps the GenServer-based BrowserAgent to expose
  browser automation as Ash actions that can be called via MCP.
  """

  use Ash.Resource

  alias Piano.Tools.BrowserAgent

  actions do
    # Navigation
    action :visit, :string do
      description "Navigate browser to a URL"

      argument :url, :string do
        allow_nil? false
        description "The URL to navigate to"
      end

      argument :format, :atom do
        description "Content format: :text, :markdown, :html, :structured"
        default :text
      end

      argument :screenshot, :boolean do
        description "Whether to take a screenshot"
        default false
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        url = input.arguments.url
        format = input.arguments.format
        take_screenshot = input.arguments.screenshot

        with {:ok, visited_url} <- BrowserAgent.visit(pid, url),
             {:ok, content} <- BrowserAgent.get_page_content(pid, format) do
          result = %{url: visited_url, content: content, format: format}

          # Take screenshot if requested
          result =
            if take_screenshot do
              {:ok, screenshot_path} = BrowserAgent.screenshot(pid)
              Map.put(result, :screenshot, screenshot_path)
            else
              result
            end

          {:ok, result}
        else
          {:error, reason} ->
            {:error, "Browser visit failed: #{reason}"}
        end
      end
    end

    # Click element
    action :click, :map do
      description "Click an element on the current page"

      argument :selector, :string do
        allow_nil? false
        description "CSS selector for the element to click"
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        selector = input.arguments.selector

        case BrowserAgent.click(pid, selector) do
          :ok ->
            {:ok, %{clicked: selector, status: "success"}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Input text
    action :input, :map do
      description "Input text into a form field"

      argument :selector, :string do
        allow_nil? false
        description "CSS selector for the input field"
      end

      argument :text, :string do
        allow_nil? false
        description "The text to input"
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        selector = input.arguments.selector
        text = input.arguments.text

        case BrowserAgent.input(pid, selector, text) do
          :ok ->
            {:ok, %{input: selector, text: text, status: "success"}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Find elements
    action :find, :map do
      description "Find elements matching a CSS selector"

      argument :selector, :string do
        allow_nil? false
        description "CSS selector to search for"
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        selector = input.arguments.selector

        case BrowserAgent.find_elements(pid, selector) do
          {:ok, elements} ->
            {:ok,
             %{
               selector: selector,
               count: length(elements),
               elements: elements
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Take screenshot
    action :screenshot, :map do
      description "Take a screenshot of the current page"

      run fn _input, _ctx ->
        pid = BrowserAgent

        case BrowserAgent.screenshot(pid) do
          {:ok, path} ->
            {:ok, %{screenshot: path, status: "success"}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Get page content
    action :get_content, :map do
      description "Extract text content from current page"

      argument :format, :atom do
        description "Content format: :text, :markdown, :html, :structured"
        default :text
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        format = input.arguments.format

        case BrowserAgent.get_page_content(pid, format) do
          {:ok, content} ->
            {:ok, %{content: content, format: format}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Get current URL
    action :current_url, :map do
      description "Get the current page URL"

      run fn _input, _ctx ->
        pid = BrowserAgent

        case BrowserAgent.current_url(pid) do
          {:ok, url} ->
            {:ok, %{url: url}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Execute JavaScript
    action :execute_script, :map do
      description "Execute JavaScript in the browser"

      argument :script, :string do
        allow_nil? false
        description "JavaScript code to execute"
      end

      argument :args, {:array, :string} do
        description "Arguments to pass to the script"
        default []
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        script = input.arguments.script
        args = input.arguments.args

        case BrowserAgent.execute_script(pid, script, args) do
          {:ok, result} ->
            {:ok, %{result: result}}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end
end
