defmodule Piano.Tools.BrowserAgentResource do
  @moduledoc """
  Ash resource wrapper for BrowserAgent tool calls via MCP.

  This resource wraps the GenServer-based BrowserAgent to expose
  browser automation as Ash actions that can be called via MCP.

  ## Output Format

  Content extraction actions (visit, get_content) save large outputs to files
  to prevent context overflow. They return:
  - `preview`: First ~100 characters of content
  - `path`: Full path to the saved file containing complete content
  - `size`: Total character count
  - `truncated`: Boolean indicating if preview was truncated

  Use the `path` to read the full content when needed via file tools.
  """

  use Ash.Resource, domain: nil

  alias Piano.Tools.BrowserAgent
  alias Piano.Tools.FileOutput

  actions do
    # Navigation
    action :visit, :map do
      description "Navigate browser to a URL. Content is saved to a file - returns preview and file path."

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
        format_ext = format_to_extension(format)

        with {:ok, visited_url} <- BrowserAgent.visit(pid, url),
             {:ok, content} <- BrowserAgent.get_page_content(pid, format) do
          # Save content to file
          case FileOutput.save(content,
                 format: format_ext,
                 prefix: "browser_visit",
                 subdirectory: "browser"
               ) do
            {:ok, file_info} ->
              result = %{
                url: visited_url,
                preview: file_info.preview,
                path: file_info.path,
                size: file_info.size,
                truncated: file_info.truncated,
                format: format
              }

              # Take screenshot if requested
              result =
                if take_screenshot do
                  {:ok, screenshot_path} = BrowserAgent.screenshot(pid)
                  Map.put(result, :screenshot, screenshot_path)
                else
                  result
                end

              {:ok, result}

            {:error, reason} ->
              {:error, "Failed to save content: #{reason}"}
          end
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
      description "Find elements matching a CSS selector. Results saved to file - returns preview and file path."

      argument :selector, :string do
        allow_nil? false
        description "CSS selector to search for"
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        selector = input.arguments.selector

        case BrowserAgent.find_elements(pid, selector) do
          {:ok, elements} ->
            # Save element data as JSON
            data = %{
              selector: selector,
              count: length(elements),
              elements: elements
            }

            case FileOutput.save_json(data,
                   prefix: "browser_find",
                   subdirectory: "browser"
                 ) do
              {:ok, file_info} ->
                {:ok,
                 %{
                   preview: file_info.preview,
                   path: file_info.path,
                   size: file_info.size,
                   truncated: file_info.truncated,
                   selector: selector,
                   count: length(elements)
                 }}

              {:error, reason} ->
                {:error, "Failed to save results: #{reason}"}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end

    # Take screenshot
    action :screenshot, :map do
      description "Take a screenshot of the current page. Returns the file path to the saved image."

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
      description "Extract text content from current page. Output saved to file - returns preview and file path."

      argument :format, :atom do
        description "Content format: :text, :markdown, :html, :structured"
        default :text
      end

      run fn input, _ctx ->
        pid = BrowserAgent
        format = input.arguments.format
        format_ext = format_to_extension(format)

        case BrowserAgent.get_page_content(pid, format) do
          {:ok, content} ->
            # Save to file
            case FileOutput.save(content,
                   format: format_ext,
                   prefix: "browser_content",
                   subdirectory: "browser"
                 ) do
              {:ok, file_info} ->
                {:ok,
                 %{
                   preview: file_info.preview,
                   path: file_info.path,
                   size: file_info.size,
                   truncated: file_info.truncated,
                   format: format
                 }}

              {:error, reason} ->
                {:error, "Failed to save content: #{reason}"}
            end

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
      description "Execute JavaScript in the browser. Result saved to file if large - returns preview and file path."

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
            # Convert result to string and save if needed
            result_str = inspect(result)

            if String.length(result_str) > 200 do
              # Save large results to file
              case FileOutput.save(result_str,
                     format: "txt",
                     prefix: "browser_script",
                     subdirectory: "browser"
                   ) do
                {:ok, file_info} ->
                  {:ok,
                   %{
                     preview: file_info.preview,
                     path: file_info.path,
                     size: file_info.size,
                     truncated: file_info.truncated,
                     result_type: "saved_to_file"
                   }}

                {:error, _reason} ->
                  # Fallback: return result directly if file save fails
                  {:ok, %{result: result}}
              end
            else
              # Small results can be returned directly
              {:ok, %{result: result}}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # Helper function to convert format atom to file extension
  defp format_to_extension(:text), do: "txt"
  defp format_to_extension(:markdown), do: "md"
  defp format_to_extension(:html), do: "html"
  defp format_to_extension(:structured), do: "json"
  defp format_to_extension(_), do: "txt"
end
