defmodule Piano.Agents.SystemPrompt do
  @moduledoc false

  alias Piano.Agents.SkillRegistry

  @spec build(Piano.Agents.Agent.t(), list()) :: String.t()
  def build(agent, tools \\ []) do
    skill_prompts = SkillRegistry.get_prompts(agent.enabled_skills)
    available_skills = SkillRegistry.format_for_system_prompt()
    base_prompt = agent.system_prompt || "You are a helpful assistant."
    soul_prompt = format_soul(agent.soul)

    [base_prompt]
    |> maybe_append(soul_prompt)
    |> maybe_append(skill_prompts)
    |> maybe_append(available_skills)
    |> maybe_append_tools(tools)
    |> Enum.join("\n\n")
  end

  defp maybe_append(parts, ""), do: parts
  defp maybe_append(parts, value), do: parts ++ [String.trim(value)]

  defp maybe_append_tools(parts, []), do: parts

  defp maybe_append_tools(parts, tools) do
    tools_text =
      tools
      |> Enum.map(&format_tool/1)
      |> Enum.join("\n")

    if tools_text == "" do
      parts
    else
      parts ++ ["Tools:\n" <> tools_text]
    end
  end

  defp format_tool(%ReqLLM.Tool{name: name, description: desc, parameter_schema: schema}) do
    params =
      schema
      |> Enum.map(fn {key, opts} ->
        required = if opts[:required], do: "required", else: "optional"
        type_str = format_type(opts[:type])
        "#{key} (#{type_str}, #{required})"
      end)
      |> Enum.join(", ")

    "#{name} - #{desc}#{format_params_suffix(params)}"
  end

  defp format_tool(%{name: name, description: desc}) do
    "#{name} - #{desc}"
  end

  defp format_tool(%{name: name}), do: "#{name}"
  defp format_tool(other), do: inspect(other)

  defp format_params_suffix(""), do: ""
  defp format_params_suffix(params), do: " (#{params})"

  defp format_type(nil), do: "any"
  defp format_type({:list, subtype}), do: "list(#{format_type(subtype)})"
  defp format_type(type) when is_atom(type), do: Atom.to_string(type)
  defp format_type(type), do: inspect(type)

  defp format_soul(nil), do: ""
  defp format_soul(""), do: ""

  defp format_soul(soul) do
    "<soul>\n#{String.trim(soul)}\n</soul>"
  end
end
