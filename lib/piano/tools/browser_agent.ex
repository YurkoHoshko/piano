defmodule Piano.Tools.BrowserAgent do
  @moduledoc """
  Headless browser automation tool using Wallaby.

  Provides a supervised GenServer for persistent browser sessions with:
  - Page visiting and content extraction
  - Screenshot capture
  - Form interaction (click, input)
  - Cookie management
  - Session persistence

  This module is designed to be used as part of the Piano supervision tree.
  """

  use GenServer
  require Logger

  alias Wallaby.Browser
  alias Wallaby.Query

  defstruct [
    :session,
    :driver,
    :config_path,
    cookies: [],
    history: [],
    current_url: nil
  ]

  # Client API

  @doc """
  Starts a browser agent process.

  ## Options
    * `:driver` - Browser driver: `:chrome` (default) or `:firefox`
    * `:config_path` - Path to session config file for persistence
    * `:name` - Process name for registration
  """
  def start_link(opts \\ []) do
    name = opts[:name] || __MODULE__
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Stop the browser agent and close the browser session.
  """
  def stop(pid \\ __MODULE__) do
    GenServer.stop(pid)
  end

  @doc """
  Visit a URL and wait for page to load.
  """
  def visit(pid \\ __MODULE__, url) do
    GenServer.call(pid, {:visit, url})
  end

  @doc """
  Get page content in the specified format.

  ## Formats
    * `:text` - Plain text extraction
    * `:markdown` - Markdown conversion
    * `:html` - Raw HTML
    * `:structured` - Structured data (title, headings, links, etc.)
  """
  def get_page_content(pid \\ __MODULE__, format \\ :text) do
    GenServer.call(pid, {:get_content, format})
  end

  @doc """
  Click an element matching the CSS selector.
  """
  def click(pid \\ __MODULE__, selector) do
    GenServer.call(pid, {:click, selector})
  end

  @doc """
  Input text into a form field.
  """
  def input(pid \\ __MODULE__, selector, text) do
    GenServer.call(pid, {:input, selector, text})
  end

  @doc """
  Clear an input field.
  """
  def clear_input(pid \\ __MODULE__, selector) do
    GenServer.call(pid, {:clear_input, selector})
  end

  @doc """
  Take a screenshot and save to file.

  If no path is provided, generates a timestamped filename.
  Returns the path where the screenshot was saved.
  """
  def screenshot(pid \\ __MODULE__, path \\ nil) do
    GenServer.call(pid, {:screenshot, path})
  end

  @doc """
  Get the current page URL.
  """
  def current_url(pid \\ __MODULE__) do
    GenServer.call(pid, :current_url)
  end

  @doc """
  Execute JavaScript in the browser and return the result.
  """
  def execute_script(pid \\ __MODULE__, script, args \\ []) do
    GenServer.call(pid, {:execute_script, script, args})
  end

  @doc """
  Load cookies from a file or list.
  """
  def load_cookies(pid \\ __MODULE__, cookies_or_path) do
    GenServer.call(pid, {:load_cookies, cookies_or_path})
  end

  @doc """
  Save cookies to a file.
  """
  def save_cookies(pid \\ __MODULE__, path) do
    GenServer.call(pid, {:save_cookies, path})
  end

  @doc """
  Get current cookies.
  """
  def get_cookies(pid \\ __MODULE__) do
    GenServer.call(pid, :get_cookies)
  end

  @doc """
  Find elements matching a CSS selector.
  Returns list of element info maps with id, class, and text.
  """
  def find_elements(pid \\ __MODULE__, selector) do
    GenServer.call(pid, {:find_elements, selector})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    driver = Keyword.get(opts, :driver, :chrome)
    config_path = Keyword.get(opts, :config_path)

    # Ensure Wallaby is configured
    Application.put_env(:wallaby, :otp_app, :piano)

    # Start Wallaby session
    case Wallaby.start_session(capabilities: build_capabilities(driver, opts)) do
      {:ok, session} ->
        state = %__MODULE__{
          session: session,
          driver: driver,
          config_path: config_path,
          cookies: [],
          history: [],
          current_url: nil
        }

        # Load initial config if provided
        state =
          if config_path && File.exists?(config_path) do
            load_config_from_file(state, config_path)
          else
            state
          end

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start browser session: #{inspect(reason)}")
        {:stop, "Failed to start browser session: #{inspect(reason)}"}
    end
  end

  @impl true
  def handle_call({:visit, url}, _from, state) do
    new_session = Browser.visit(state.session, url)
    current_url = Browser.current_url(new_session)

    # Wait for page to settle
    Process.sleep(500)

    new_state = %{
      state
      | session: new_session,
        current_url: current_url,
        history: [current_url | state.history]
    }

    {:reply, {:ok, current_url}, new_state}
  end

  @impl true
  def handle_call({:get_content, format}, _from, state) do
    html = Browser.page_source(state.session)

    result =
      case format do
        :html ->
          {:ok, html}

        :text ->
          extract_text(html)

        :markdown ->
          html_to_markdown(html)

        :structured ->
          extract_structured_content(html)

        _ ->
          {:ok, html}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:click, selector}, _from, state) do
    new_session =
      state.session
      |> Browser.click(Query.css(selector))

    # Wait for page to settle after click
    Process.sleep(500)

    new_state = %{state | session: new_session}
    {:reply, :ok, new_state}
  rescue
    e ->
      Logger.warning("Click failed for selector '#{selector}': #{inspect(e)}")
      {:reply, {:error, "Click failed: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:input, selector, text}, _from, state) do
    new_session =
      state.session
      |> Browser.fill_in(Query.css(selector), with: text)

    new_state = %{state | session: new_session}
    {:reply, :ok, new_state}
  rescue
    e ->
      Logger.warning("Input failed for selector '#{selector}': #{inspect(e)}")
      {:reply, {:error, "Input failed: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:clear_input, selector}, _from, state) do
    new_session =
      state.session
      |> Browser.clear(Query.css(selector))

    new_state = %{state | session: new_session}
    {:reply, :ok, new_state}
  rescue
    e ->
      Logger.warning("Clear failed for selector '#{selector}': #{inspect(e)}")
      {:reply, {:error, "Clear failed: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:screenshot, _path}, _from, state) do
    # Generate proper screenshot path
    screenshot_dir = "/piano/agents/mcp-outputs/screenshots"
    File.mkdir_p!(screenshot_dir)

    timestamp = System.os_time(:millisecond)
    target_path = "#{screenshot_dir}/screenshot_#{timestamp}.png"

    # Use Wallaby's take_screenshot (saves to default location)
    new_session = Browser.take_screenshot(state.session)

    # Get the screenshot path from Wallaby's default location
    wallaby_path = List.first(new_session.screenshots)

    new_state = %{state | session: new_session}

    if wallaby_path && File.exists?(wallaby_path) do
      # Copy from Wallaby's location to our target location
      case File.cp(wallaby_path, target_path) do
        :ok ->
          Logger.info("Screenshot saved", path: target_path)
          {:reply, {:ok, target_path}, new_state}

        {:error, reason} ->
          Logger.warning("Failed to copy screenshot: #{inspect(reason)}")
          # Return Wallaby's path as fallback
          {:reply, {:ok, wallaby_path}, new_state}
      end
    else
      {:reply, {:error, "Screenshot not created"}, new_state}
    end
  rescue
    e ->
      Logger.warning("Screenshot failed: #{inspect(e)}")
      {:reply, {:error, "Screenshot failed: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call(:current_url, _from, state) do
    url = Browser.current_url(state.session)
    {:reply, {:ok, url}, %{state | current_url: url}}
  end

  @impl true
  def handle_call({:execute_script, script, args}, _from, state) do
    {result, new_session} = Browser.execute_script(state.session, script, args)
    new_state = %{state | session: new_session}
    {:reply, {:ok, result}, new_state}
  rescue
    e ->
      Logger.warning("Script execution failed: #{inspect(e)}")
      {:reply, {:error, "Script execution failed: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:load_cookies, cookies_or_path}, _from, state) do
    cookies =
      if is_binary(cookies_or_path) && File.exists?(cookies_or_path) do
        cookies_or_path
        |> File.read!()
        |> Jason.decode!()
      else
        cookies_or_path
      end

    new_session =
      Enum.reduce(cookies, state.session, fn cookie, session ->
        Browser.set_cookie(
          session,
          cookie["name"] || cookie[:name],
          cookie["value"] || cookie[:value],
          domain: cookie["domain"] || cookie[:domain],
          path: cookie["path"] || cookie[:path] || "/",
          secure: cookie["secure"] || cookie[:secure] || false,
          http_only: cookie["httpOnly"] || cookie[:http_only] || false
        )
      end)

    new_state = %{state | session: new_session, cookies: cookies}
    {:reply, :ok, new_state}
  rescue
    e ->
      Logger.warning("Failed to load cookies: #{inspect(e)}")
      {:reply, {:error, "Failed to load cookies: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:save_cookies, path}, _from, state) do
    # Get cookies via JavaScript
    script = """
    return document.cookie.split(';').map(function(c) {
      var parts = c.trim().split('=');
      return {name: parts[0], value: parts[1] || '', domain: window.location.hostname, path: '/'};
    });
    """

    {cookies, new_session} = Browser.execute_script(state.session, script, [])

    File.write!(path, Jason.encode!(cookies, pretty: true))

    new_state = %{state | session: new_session, cookies: cookies}
    {:reply, {:ok, cookies}, new_state}
  rescue
    e ->
      Logger.warning("Failed to save cookies: #{inspect(e)}")
      {:reply, {:error, "Failed to save cookies: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call(:get_cookies, _from, state) do
    script = """
    return document.cookie.split(';').map(function(c) {
      var parts = c.trim().split('=');
      return {name: parts[0], value: parts[1] || ''};
    });
    """

    {cookies, new_session} = Browser.execute_script(state.session, script, [])
    new_state = %{state | session: new_session, cookies: cookies}
    {:reply, {:ok, cookies}, new_state}
  rescue
    e ->
      Logger.warning("Failed to get cookies: #{inspect(e)}")
      {:reply, {:error, "Failed to get cookies: #{inspect(e)}"}, state}
  end

  @impl true
  def handle_call({:find_elements, selector}, _from, state) do
    elements = Browser.all(state.session, Query.css(selector))

    element_info =
      Enum.map(elements, fn el ->
        %{
          id: Browser.attr(el, Query.css("#"), "id"),
          class: Browser.attr(el, Query.css("."), "class"),
          text: Browser.text(el)
        }
      end)

    {:reply, {:ok, element_info}, state}
  rescue
    e ->
      Logger.warning("Find elements failed for selector '#{selector}': #{inspect(e)}")
      {:reply, {:error, "Find failed: #{inspect(e)}"}, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.session do
      Wallaby.end_session(state.session)
    end

    :ok
  end

  # Private functions

  defp build_capabilities(:chrome, opts) do
    %{
      chromeOptions: %{
        args:
          [
            "--headless",
            "--no-sandbox",
            "--disable-dev-shm-usage",
            "--disable-gpu",
            "--window-size=1920,1080",
            "--disable-blink-features=AutomationControlled"
          ] ++ if(opts[:user_agent], do: ["--user-agent=#{opts[:user_agent]}"], else: [])
      }
    }
  end

  defp build_capabilities(:firefox, opts) do
    %{
      "moz:firefoxOptions" => %{
        args: ["-headless"],
        prefs: %{
          "general.useragent.override" =>
            opts[:user_agent] ||
              "Mozilla/5.0 (X11; Linux x86_64; rv:109.0) Gecko/20100101 Firefox/115.0"
        }
      }
    }
  end

  defp extract_text(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        text =
          document
          |> Floki.find("body")
          |> Floki.text(sep: "\n")
          |> normalize_whitespace()

        {:ok, text}

      {:error, reason} ->
        {:error, "Failed to parse HTML: #{inspect(reason)}"}
    end
  end

  defp html_to_markdown(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        # Find body element, fallback to document if no body exists
        body =
          case Floki.find(document, "body") do
            [] -> document
            [body_element | _] -> body_element
          end

        markdown =
          body
          |> Floki.children()
          |> Enum.map_join("\n\n", &element_to_markdown/1)
          |> normalize_whitespace()

        {:ok, markdown}

      {:error, reason} ->
        {:error, "Failed to parse HTML: #{inspect(reason)}"}
    end
  end

  defp extract_structured_content(html) do
    case Floki.parse_document(html) do
      {:ok, document} ->
        content = %{
          title: extract_title(document),
          headings: extract_headings(document),
          paragraphs: extract_paragraphs(document),
          links: extract_links(document),
          lists: extract_lists(document)
        }

        {:ok, content}

      {:error, reason} ->
        {:error, "Failed to parse HTML: #{inspect(reason)}"}
    end
  end

  defp extract_title(document) do
    document
    |> Floki.find("title")
    |> Floki.text()
    |> String.trim()
  end

  defp extract_headings(document) do
    document
    |> Floki.find("h1, h2, h3, h4, h5, h6")
    |> Enum.map(fn el ->
      tag = el |> elem(0)
      text = Floki.text(el)
      {tag, text}
    end)
  end

  defp extract_paragraphs(document) do
    document
    |> Floki.find("p")
    |> Enum.map(&Floki.text/1)
    |> Enum.filter(&(String.length(&1) > 0))
  end

  defp extract_links(document) do
    document
    |> Floki.find("a[href]")
    |> Enum.map(fn el ->
      href = Floki.attribute(el, "href") |> List.first()
      text = Floki.text(el)
      %{href: href, text: text}
    end)
  end

  defp extract_lists(document) do
    document
    |> Floki.find("ul, ol")
    |> Enum.map(fn el ->
      items = el |> Floki.find("li") |> Enum.map(&Floki.text/1)
      {elem(el, 0), items}
    end)
  end

  defp element_to_markdown({tag, _attrs, children}) when tag in ["h1", "h2"] do
    text = Floki.text(children)
    level = if tag == "h1", do: "# ", else: "## "
    level <> text
  end

  defp element_to_markdown({tag, _attrs, children}) when tag in ["h3", "h4", "h5", "h6"] do
    text = Floki.text(children)
    level = String.duplicate("#", String.to_integer(String.replace_leading(tag, "h", "")))
    level <> " " <> text
  end

  defp element_to_markdown({"p", _attrs, children}) do
    Floki.text(children)
  end

  defp element_to_markdown({"ul", _attrs, children}) do
    children
    |> Enum.filter(fn el -> match?({"li", _, _}, el) end)
    |> Enum.map_join("\n", fn {"li", _, li_children} -> "- " <> Floki.text(li_children) end)
  end

  defp element_to_markdown({"ol", _attrs, children}) do
    children
    |> Enum.filter(fn el -> match?({"li", _, _}, el) end)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {{"li", _, li_children}, i} ->
      "#{i}. " <> Floki.text(li_children)
    end)
  end

  defp element_to_markdown({"blockquote", _attrs, children}) do
    "> " <> Floki.text(children)
  end

  defp element_to_markdown({"a", attrs, children}) do
    text = Floki.text(children)
    href = Floki.attribute(attrs, "href") |> List.first() || ""
    "[#{text}](#{href})"
  end

  defp element_to_markdown({_tag, _attrs, children}) do
    Floki.text(children)
  end

  defp element_to_markdown(text) when is_binary(text), do: text

  defp normalize_whitespace(text) do
    text
    |> String.replace(~r/[ \t]+/, " ")
    |> String.replace(~r/\n{3,}/, "\n\n")
    |> String.trim()
  end

  defp load_config_from_file(state, path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, config} ->
            %{state | cookies: config["cookies"] || []}

          {:error, _} ->
            state
        end

      {:error, _} ->
        state
    end
  end
end
