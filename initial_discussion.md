HIGH LEVEL DESCRIPTION


Elixir-Based Multi-Agent Chat System Architecture
Overview and Goals
We are designing an Elixir-based multi-channel AI assistant system that supports real-time chat on a
web UI and via Telegram. The system allows a single user to chat with one or more AI agents (LLM-powered
assistants) using a unified conversation thread concept (instead of "sessions"), with the ability to fork
conversation threads and even switch between different agents mid-conversation. Key requirements
include:
•
•
•
•
•
•
•
Phoenix LiveView UI for both a user chat interface and an admin dashboard (single-user system for
now).
Telegram Bot integration using ExGram (Telegram API library) with Req (HTTP client) for sending/
receiving messages.
A generic message gateway that funnels incoming messages (from LiveView or Telegram) into a
processing pipeline. This pipeline should route the message to the appropriate agent and handle
the LLM response generation, while emitting lifecycle events (e.g. "agent is thinking", "response
ready") for UI updates.
Domain modeling with the Ash Framework for clean organization of resources (Threads, Messages,
Agents, etc.), including Ash actions for creating messages, forking threads, toggling agent tools, etc.
The data will persist in a SQLite database (with easy future export to other formats).
Agent configuration management: Each agent has configurable skills and tools. Skills (loaded from
an .agents/skills directory) define the agent’s knowledge or behaviors, and tools (Elixir
functions that can be invoked by the agent) can be toggled on/off per agent via the admin UI.
LLM integration using ReqLLM to call external or local model APIs (with a plan to use a Llama-
based OpenAI-compatible service like llama-swap as the completion backend). We aim to support
streaming responses and tool usage during LLM calls.
Robust asynchronous processing of messages using GenStage for concurrency and back-pressure
1
, and a comprehensive testing strategy (unit tests for each component and end-to-end tests
simulating full conversations).
Below we break down the architecture into modules, domains, and workflows, then describe how
everything fits together and how it can be tested thoroughly.
Phoenix LiveView Interfaces (Chat UI & Admin Dashboard)
User Chat Interface: We will build a LiveView ( MyAppWeb.Live.ChatLive ) that provides a real-time chat
experience. This LiveView will display the current thread’s messages and allow the user to send new
messages. We will leverage LiveView’s streaming capabilities to append new messages to the chat log
without reloading the whole page 2 3
. For example, when the user sends a message, we use
Phoenix.LiveView.push_event or LiveView streams to optimistically render the user’s message, then
update with the agent’s reply when it arrives. The UI may also show typing indicators or partial progress,
driven by lifecycle events from the backend (more on that in the pipeline section). The user can switch
1
threads (e.g. from a list of conversation threads) or fork a new thread from a given point. If multiple agents
are available, the UI can offer a dropdown to select the “active agent” for the next question (defaulting to
the thread’s primary agent).
Admin Dashboard: Administration and configuration will be handled through a LiveView-based admin UI,
accessible only to the authorized user. We’ll integrate this with Phoenix LiveDashboard or use a similar
approach for security. On server start, the application can generate a random access token and print it to
the console – the user must provide this token (e.g. as a query param or login) to access admin pages,
ensuring that only someone with console access (the single user in this case) can use the admin interface.
The admin UI will include:
•
Agent Management Page: A LiveView ( MyAppWeb.Live.AgentConfigLive ) showing a list of AI
agents. For each agent, it will list the available tools and skills with toggle switches. The user can
enable or disable specific tools/skills on the fly. When a toggle is changed, an Ash action or context
function updates the agent’s configuration (persisting it in the database so it’s remembered on
restart). For example, if “WebSearch” is a tool, disabling it will prevent the agent from calling that tool
until re-enabled. This page can also allow editing agent details (name, description, model to use,
etc.) and possibly viewing an agent’s prompt or skill definitions.
•
Thread/Conversation Monitor (optional): An admin view to see all conversation threads, possibly
with the ability to click into any thread to inspect messages. This helps in debugging or moderating
the agent’s behavior. Since it’s a single-user system, this is less critical, but it lays groundwork for
multi-user future.
All LiveView modules will be housed under MyAppWeb and use standard Phoenix patterns. We will secure
the admin LiveViews either by mounting them under Phoenix.LiveDashboard (which can use an auth
plug or require the token in config) 4 5
or by implementing a custom authentication that checks the
startup token. The chat UI itself might be public (or also behind the token if we want absolutely no
unauthorized access).
LiveView Event Flow: When the user types a message and hits “send” (or presses enter), the ChatLive will
handle an event (e.g. handle_event("send_message", %{content: ...}, socket) ). In that handler,
we will call our message gateway function (described below) to process the message. We immediately
append the user’s message to the UI via LiveView stream, and then perhaps show a “... thinking ...” indicator
(which could be an empty placeholder message from the agent or a loading spinner) while waiting for the
response. The response will be delivered via PubSub events or direct push from the pipeline, and the
LiveView will update the UI with the new agent message (replacing the spinner if needed).
Telegram Bot Integration (ExGram + Req)
We will run a Telegram bot to allow chatting via Telegram as an alternative frontend. Using ExGram (an
Elixir Telegram bot library), we’ll implement a bot module (e.g. MyApp.Telegram.Bot ) that listens for
incoming updates and sends outgoing messages. ExGram can handle long polling or webhooks; for
simplicity, we might use polling (ExGram’s :long_poll mode) so the bot can run without needing a
public webhook URL. We’ll supply the bot token from config and supervise the bot process as part of the
application start. An example of defining a simple ExGram bot:
2
defmodule MyApp.Telegram.Bot do
use ExGram.Bot, name: :my_bot
def bot(), do: :my_bot
# Handle /start command
def handle({:command, "start", _msg}, context) do
answer(context, "Hello! You can start chatting with the AI assistant now.")
end
# Handle any text message
def handle({:text, text, msg}, context) do
# Forward the text to our message gateway, including Telegram metadata
MyApp.ChatGateway.handle_incoming(text, :telegram, %{chat_id: msg.chat.id,
from_id: msg.from.id})
# (We won't send an immediate reply here; the reply will be sent
asynchronously)
:ok
end
end
This illustrates how ExGram uses pattern matching on the message tuple to route commands and
messages 6 7
. In our case, any text message (without a leading slash command) will be treated as user
input to the assistant. The bot’s handle/2 calls our central gateway
( MyApp.ChatGateway.handle_incoming/3 in this sketch) with the message text, specifying the channel
( :telegram ) and some metadata (Telegram chat ID, user ID) so we know where to send the response.
For sending the agent’s responses back to Telegram, we have a couple of options:
•
Use ExGram’s helper to answer the context with a message. Since our processing is async, we can’t
call answer within the handle (as we return immediately). Instead, our pipeline (or gateway) will
call an ExGram API function later to send the message. ExGram provides functions like
ExGram.send_message(chat_id, text, options) internally, but we might use Req HTTP
client directly to call the Telegram Bot API endpoint (this is feasible because the Bot API is just HTTPS
calls). Using Req could simplify things or allow custom handling (the user requested using Req). We
could do something like:
Req.post!("https://api.telegram.org/bot#{@bot_token}/sendMessage", json: %
{chat_id: chat_id, text: reply_text})
This can be wrapped in a function MyApp.Telegram.send_message(chat_id, text) for reuse.
•
Additionally, we can use the Telegram API method sendChatAction with action "typing" to
indicate the bot is processing. The gateway/pipeline can trigger this as soon as a user message is
received on Telegram, so the user sees the "Bot is typing..." indicator in the chat. For example, using
3
Req: Req.post!("https://api.telegram.org/bot.../sendChatAction", json: %
{chat_id: id, action: "typing"}) . This corresponds to setting a lifecycle event when the
agent starts working. We will incorporate this in the event pipeline.
Session Mapping Across Devices: Since we want the same conversation thread to continue whether the user
is on the web or Telegram, we need to map Telegram messages to a specific thread. We’ll likely treat the
single user’s identity as the bridge: if the Telegram from_id matches our single user, we use that user’s
currently active thread. We can maintain an “active thread” pointer per user (and even per device if desired).
A simpler approach: if there’s only one thread active at a time, just route everything there unless a special
command is given to switch threads. Alternatively, we could allow commands like /thread 3 to switch
the active thread via Telegram. For now, assume the user will primarily stick to one thread at a time. We will
store enough info in the message records to identify source and target: each Message will have a source
field (e.g. :web or :telegram ) and possibly a telegram_chat_id if source is Telegram, so we know
where to respond. The gateway will use this to send replies to the correct channel.
In summary, the Telegram Bot process will act as an adapter that converts Telegram updates to our internal
message format and vice versa. This modular approach means adding more channels (Slack, SMS, etc.) in
the future would be as simple as writing another adapter that calls ChatGateway.handle_incoming.
Ash Domains and Resources (Threads, Messages, Agents)
Using the Ash Framework, we will define our core data models as Ash resources within logical domains
8
9
. Ash will handle persistence (using Ecto with SQLite) and provide a set of actions on each resource for
creating, reading, and updating them 10 5
. This gives us a robust, declarative way to manage our data
and business logic. We anticipate two main domains:
•
•
Chat Domain ( MyApp.Chat ): Contains resources related to conversations:
Thread ( MyApp.Chat.Thread ): Represents a conversation thread (analogous to a chat room or
session). Attributes might include id (UUID primary key), an optional title or topic , a
inserted_at timestamp, etc. We might also track a status ( :active or :archived ). Each
Thread can belong to a User (for multi-user support later), but for now in a single-user context this is
less critical. (We may still include a user_id to future-proof, but allow it to be nil or default to the
single user). Most importantly, a Thread has a relationship to many messages:
relationships do
# belongs_to :user, MyApp.Accounts.User, allow_nil?: true (future use)
has_many :messages, MyApp.Chat.Message, destination_field: :thread_id
# possibly: belongs_to :primary_agent, MyApp.Agents.Agent, allow_nil?:
true
end
This means one thread contains a list of messages 11
. Ash will let us easily load a thread with its
messages, filter by thread, etc., without manual queries 12 5
. If we decide to mark a “primary
agent” for the thread (the default agent that replies), we can include a
belongs_to :primary_agent relationship. However, since we allow per-message agent
4
selection, the thread’s primary agent is more of a default. We’ll still store the agent at the message
level (see Message below).
Actions: We will have at least the default create and read actions. We can define a custom
create if we want to set defaults (like started_at). For example, an action create :start_thread
that might accept a title or initial parameters. We will also add a custom action for forking a thread:
e.g. action :fork_thread (could be a create action or a read that returns a new thread).
This action would take an argument of an existing message ID (the point at which to fork) or an
entire thread ID to duplicate. The implementation (possibly via an Ash after_action hook or a
small custom function) will:
- Load the original thread’s messages up to the given message (inclusive or exclusive based on
design).
- Create a new Thread record (with perhaps a reference to its “parent” thread for history).
- Copy those messages into the new thread (each with the new thread_id). We may need to iterate
and create messages; Ash could do this with a changeset in a transaction, or we can use plain Ecto
for batch insert since it might be complex to express purely in the DSL.
We’ll mark the new thread’s fork origin (could be attributes like forked_from_thread_id and
forked_from_message_id for traceability). This allows the UI to indicate a thread was forked
from another at a specific point.
•
Message ( MyApp.Chat.Message ): Represents a single chat message in a thread. Attributes: id
(UUID), content (the text content), role or sender_type (could be :user or :agent ),
timestamp ( inserted_at ), source (e.g. :liveview or :telegram for audit), and crucially
a reference to which agent this message was addressed to or produced by. We can have an
attribute like agent_id that is nil for user messages and set to the agent’s ID for messages that
are agent replies. For user messages, we might also set agent_id to the intended recipient agent
(which could be the thread’s primary agent or one explicitly chosen by the user). This way, each
message knows which agent was involved. If the conversation alternates between agents, we’ll have
messages with different agent_ids in one thread.
Relationships for Message:
relationships do
belongs_to :thread, MyApp.Chat.Thread, allow_nil?: false
belongs_to :agent, MyApp.Agents.Agent, allow_nil?: true
# agent who sent or target agent
end
This indicates each Message is linked to its Thread (many-to-one) and optionally to an Agent agent messages). If in future we have user accounts, we might add belongs_to :user but in a single-user scenario we can assume all user messages come from the same user.
11
(for
as well,
Actions: We will use Ash’s define a custom action create send_message action for messages when a new message comes in. We might
on Thread or a standalone context function (since sending
5
•
•
a message involves side-effects outside the DB). One approach: define on Thread a create action
like create :post_user_message that accepts content and maybe agent_id (for target
agent) and internally creates a Message associated with the thread. But since we also need to trigger
the processing pipeline, we may handle that outside of Ash. A cleaner separation is:
- Use Ash just to store the message (for logging and future retrieval), i.e.
Ash.create(MyApp.Chat.Message, ... ) when a user sends something or when an agent
reply is ready.
- The processing pipeline will not be fully expressed as an Ash action (because calling an LLM and
waiting for response is not a quick DB operation). Instead, the pipeline will use the data in Ash but
run in separate processes.
We will use Ash actions for normal CRUD (reading messages, perhaps listing threads with preloaded
messages, etc.). For example, a read action on Thread to get a thread with all its messages could use
Ash’s prepare build(load: [:messages]) to auto-preload messages 5 13
. This will simplify
the LiveView’s task when loading a conversation.
Agents Domain ( MyApp.Agents ): Contains resources for AI agents and possibly their tool
configurations.
Agent ( MyApp.Agents.Agent ): Represents an AI agent (persona or model configuration).
Attributes might include id , name (e.g. "GPT-4 Assistant" or "Math Guru"), description (for
display), and fields for LLM setup such as model (which could be a string like "openai:gpt-4"
or "local:vicuna-13b" etc. to instruct ReqLLM which provider/model to use), and possibly
prompt_prefix or system instructions for that agent. We also need to represent which tools and
skills are enabled for each agent.
For tools/skills, since they are code-defined, we might simply keep lists of their identifiers in the
Agent resource: e.g. enabled_tools: {:array, :string} type or a JSON column. Ash supports
JSON and array types (with constraints). We can store something like ["calculator",
"web_search", "code_executor"] as the enabled tools. Similarly enabled_skills:
{:array, :string} for skill names. Alternatively, we could create separate resources like
AgentTool join table, but given the small scale and single user, lists are simpler. The admin UI will
load all available tool names (from our code registry) and compare with agent.enabled_tools to
show toggles. Updating the toggles would call an Ash update action on the Agent (e.g.
update :configure that accepts lists of tools/skills). This satisfies the requirement to “expose
Ash actions that allow the system/user to adjust tools” – by having an update action, any changes via
the UI are done through Ash, enforcing any rules we set (for example, we could add a validation that
at least one tool must remain enabled if we want).
Since tools are implemented in Elixir code (not in the database), the Agent resource mainly stores
which tools are allowed. The actual tool definitions (what they do) live in code (or are dynamically
loaded). Skills are similar: they might correspond to files or modules, but we store which ones the
agent uses.
Actions: Aside from default read and update , we might add convenience actions like
enable_tool or disable_tool as separate actions (these could internally just call the update
6
with modified list, but Ash can define them for clarity). For example:
update :enable_tool do
argument :tool, :string, allow_nil?: false
change manage_relationship(:tools, type: :append, on_no_match: :ignore)
# pseudo-code if tools were a relationship
# If tools is an array attribute, we might do a custom change that uses
Ash.Changeset.append_to_attribute/3
end
But given complexity, a simpler approach is just one action list of tools and skills to set.
update_config that accepts the full
We should also consider an action to create a new agent (if the user can add agents via UI). For now,
we might seed a default agent in the DB at startup (with a migration or a script) so there's something
to use. The user story didn't explicitly mention creating agents at runtime, but having that ability is
nice (the admin could configure a second agent with a different model or persona, for example). We
can support create :register_agent with fields for name, model, etc.
•
(Optional) Accounts Domain ( MyApp.Accounts.User ): If we foresee multi-user in future, we
could define a User resource. For now, we might have a dummy single user. Ash can easily
accommodate a User resource with fields like name, etc., and a relationship such that Thread
belongs to User 14
. In the AshTherapy example, they did exactly that: Conversation (Thread)
belongs_to User 11
. We can include this but since it's a single-user system now, we may skip actual
login functionality. We will keep it in mind in our design (e.g. design Thread with a user_id that can
be nil or a constant) for future expansion.
Ash’s approach ensures our data layer is well-structured. By declaring attributes, relationships, and
actions, Ash will manage a lot of boilerplate for us, from migrations to context functions 15 16
. We get
built-in support for filtering, sorting, and loading associations (for example, an action to get a thread by id
can preload all its messages in one go 17
).
Data Storage: We will use SQLite via Ecto as the Ash data layer (Ash works with Ecto adapters). This is
lightweight and requires no external DB setup, ideal for early development and single-user deployment.
Ash can auto-generate the migrations for our resources (we run mix ash.codegen && mix
ash.migrate to create the SQLite schema from our resource definitions 18
). SQLite will store threads,
messages, agents, etc. We also plan to later support exporting an agent to a file format (perhaps to share
agent definitions), but that can be built as needed (e.g. an action to dump Agent config and skills to JSON).
Agent Capabilities: Tools and Skills System
A core feature is that agents can have tools and skills that extend their functionality. In our architecture:
•
Tools are functions (Elixir implementations) that an LLM agent can invoke to perform specific
operations (e.g. search the web, do math, run code, fetch weather, etc.). These will be implemented
7
as native Elixir functions or modules. We will register tools with the LLM client (ReqLLM) such that
the model can call them when needed. For example, using ReqLLM’s API we can define a tool with a
name, description, and callback function 19
. The callback executes the actual code and returns a
result. We saw an example where a weather_tool is defined with a callback to return a weather
string 19
. We can create similar tool definitions for our system. Perhaps we maintain a module
MyApp.Agents.Tools where we define available tools. Each tool might be a struct or we use
ReqLLM.tool/1 to create a tool struct at runtime. Tools might include: "calculator" ,
"wiki_search", "code_runner" , etc., depending on what we implement.
The agent’s allowed tools (enabled/disabled via the admin UI) control which of these tool callbacks are
passed into the LLM call. For instance, if the agent has a Calculator tool but the admin toggled it off,
then when we call ReqLLM.generate_text for that agent, we will not include that tool in the tools:
[...] list, so the LLM cannot invoke it. This provides a way to constrain or expand the agent’s abilities at
runtime.
•
Skills in this context likely refer to pieces of prompt or behavior the agent can use. The mention of
".agents/skills directory (as standard dictates)" suggests a convention: possibly each skill is a text file
or module containing prompt instructions, knowledge, or chain-of-thought logic. For example, a skill
could be "TranslationSkill" which, if enabled, means the agent has some system prompt telling it how
to translate languages, or a skill "TherapyStyle" that gives it a certain tone. These could be static
prompt snippets that get concatenated to the system or user prompt if enabled. Another
interpretation is that skills are like tool-specific skills or chain-of-thought strategies implemented in
code. Since the question references a standard, we’ll assume skills are loaded from files dynamically.
Implementation: On application startup, we scan .agents/skills directory for skill definitions. These
could be .md or .txt files with prompt text, or .ex files defining some behavior. A simple approach:
treat each skill as a chunk of text with a name. We load them into a map, e.g. %{"TherapyAdvice" =>
"...some instructions...", "ScienceExpert" => "...instructions..."} . Then, for each
agent, if a skill is enabled, when building the prompt for the LLM we include that text (perhaps as part of
the system role message or as an additional context message). If skills are more complex (like adding extra
tool logic), we might handle that differently, but likely it's prompt-based.
The admin UI will list all available skill names from the directory, and allow toggling them per agent similar
to tools. The Agent resource’s enabled_skills field will store which skills are active.
•
Agent Execution Flow: When our pipeline is about to generate a response using an agent, it needs
to gather everything: the conversation context (prior messages), the agent’s own configuration (e.g.
model choice), and the enabled tools/skills. We’ll do something like:
# Pseudocode:
agent =
... # loaded from DB
context_messages =
... # last N messages from thread for context
tools = MyApp.Agent.ToolRegistry.get_tools(agent.enabled_tools)
skills_prompts = MyApp.Agent.SkillRegistry.prompts_for(agent.enabled_skills)
system_prompt = agent.system_prompt || "You are a helpful assistant."
# Possibly append skills to system prompt
full_system_msg = system_prompt <> "\n" <> Enum.join(skills_prompts,
"\n")
8
req_messages = [
%{role: "system", content: full_system_msg} |
Enum.map(context_messages, &%{role: &1.role, content: &1.content}) ++
[%{role: "user", content: new_user_message}]
]
response = ReqLLM.generate_text!(agent.model, req_messages, tools: tools)
The above constructs the message history and passes the tool list. If streaming, we might use
ReqLLM.stream_text and handle partial chunks. Tools defined via ReqLLM.tool have their callbacks
which will be executed if the LLM decides to call them (the LLM’s output would include a special format that
ReqLLM recognizes to invoke the callback). This means our agent can do things like get_weather in the
middle of a conversation and our Elixir code will fetch it and feed the result back to the LLM, all mediated by
ReqLLM. This is a powerful way to integrate tools 19
, and since the tools are just Elixir functions, we have
full control (they could even call external APIs or run local code – for potentially dangerous operations like
running code, we’d want sandboxing, possibly via Docker as hinted; see below).
•
Sandboxing (Future): The user noted possibly using Docker for sandboxing. If one of the tools is a
"Code Execution" tool that runs user-provided code or agent-written code, we must ensure security
(not letting arbitrary code harm the host). A strategy is to run such code inside a Docker container or
an isolated OS process. Implementing this is out of scope for the initial architecture, but our design
will accommodate it: we can implement a CodeRunnerTool whose callback sends code to a
separate service or container and returns the output. For now, we might not include a live code
execution tool, or if we do (for demo), clearly mark it experimental. The architecture is flexible to add
this later.
In summary, tools and skills extend agent behavior. They are primarily defined in code (so not Ash
resources themselves), but their usage is controlled via data (the Agent resource config). This hybrid
approach gives us dynamic control with compile-time safety. We will ensure the admin can intuitively toggle
these, and the system respects those toggles when constructing prompts and selecting which tool callbacks
to allow.
Message Processing Pipeline (GenStage Workflow)
At the heart of the system is the asynchronous pipeline that processes incoming messages and produces
agent responses. We will use GenStage, Elixir’s framework for building producer-consumer pipelines, to
handle this flow in a concurrent and back-pressured way 1 20
. The goals of using GenStage are to:
•
•
•
•
Decouple message ingestion from message processing (so front-ends don’t block on heavy LLM
calls).
Enable concurrency: multiple messages (especially from different threads or to different agents) can
be processed in parallel, up to limits we define.
Maintain ordering where needed: e.g. ensure messages within the same thread/agent are processed
sequentially to preserve conversation context, while allowing different threads to proceed
concurrently.
Emit lifecycle events at various stages of processing, which we can use to update UIs (LiveView or
Telegram) in real time.
9
Pipeline Stages: We propose a three-stage GenStage pipeline:
1. Producer – Message Ingestion: This stage receives raw incoming messages (user queries). We will
implement a module MyApp.ChatGateway (or MyApp.MessageBroker ) that holds a GenStage
producer. When either LiveView or Telegram calls ChatGateway.handle_incoming(content, source,
meta) , this function will do a few things:
- Determine the target thread and agent for this message. For example, if the UI passes along a
thread_id and maybe an agent_id (if the user explicitly chose an agent), we use those; otherwise,
default to the thread’s primary agent. If the message comes from Telegram, we map the Telegram user to
the thread as discussed and use that thread’s agent.
- Create a Message record in the database via Ash (with role “user”, content, thread reference, agent
reference if any, and source info). Storing it now ensures it’s not lost even if processing fails.
- Enqueue the message into the GenStage producer. We can call GenStage.cast on the producer with
the message event (containing at least the message ID or full content, thread, agent info). The producer will
then emit this event downstream.
This producer will be a simple GenStage that buffers events until a consumer asks for them. We can also
make it push-based (GenStage can push as events come in, since we likely want immediate processing)
21
22
. But GenStage’s back-pressure means if our processing slows down and the queue grows, we can
handle that gracefully.
1.
Producer-Consumer – Agent Dispatch: This stage subscribes to the Producer and acts as a
dispatcher/processor. We might actually have multiple producer-consumer stages, one per agent or
thread, by using partitioning. For example, we can start a separate GenStage pipeline for each agent,
or use a single GenStage with tagging. Another approach is to use Broadway (built on GenStage)
which has built-in partitioning by keys (for instance, partition by thread_id to ensure order per
thread). However, to keep things explicit, let's design manually:
The Producer-Consumer stage ( MyApp.AgentStage ) will receive a message event, look at which agent
(ID) it’s targeted to, and then perform the LLM call for that agent. If we want to parallelize by agent, we can
start multiple consumers each filtering events by agent. GenStage allows having multiple consumers and
one can filter events if we implement some logic. Alternatively, we maintain one GenStage pipeline but
within it, when an event comes in, we spawn a Task for the LLM call. That could break ordering though. A
robust solution is to use partitioned queues: e.g., use the partition option in GenStage or simply route
events to different named processes by agent.
A simpler design: One message at a time per agent. We can enforce this by storing a state map of agents -
> busy/free. If a new message for agent X comes while X is busy, we hold it (or GenStage naturally back-
pressures if a consumer isn’t ready). But if it’s for a different agent Y, we can process concurrently. Since the
system is single-user, and likely one thread at a time, this might not even be an issue initially. But if multiple
threads (maybe user forks one and continues both?), then potentially two agents could run concurrently.
In implementation, we will likely use Broadway to simplify this: with Broadway, we can use its concurrency
and partition features. But since the task suggests GenStage specifically, let's stick to that conceptually. We
can implement the Producer-Consumer to subscribe to Producer with a min_demand / max_demand and
allow concurrency of N. If we want to partition by agent, we might spin up N separate consumer processes
each filtering on a certain agent. That might be overkill now. Instead, we assume the user won't spam
10
multiple queries at once to overwhelm it. We'll design with potential extension: we tag each event with
agent_id (and thread_id ). The consumer stage can use that to manage context.
Lifecycle events: As this stage works on an event, it will emit events for different steps. For example: -
Start: Immediately when it picks up a message event, it can broadcast a "processing_started" event
(including thread_id and maybe message_id). Our LiveView (if subscribed to the thread’s topic) could receive
that and show a typing indicator. Also, for Telegram, we could here call sendChatAction(typing) via the
Telegram adapter. - Tool usage: If the LLM decides to use a tool, we might emit "tool_invocation" events or
simply log them. (ReqLLM might handle tool calls internally, but we can hook in via callbacks to know when
a tool is called and completed, to potentially notify UI or just for logging). For a web UI, we could display
something like "Agent used Weather tool" if we wanted transparency. This might be advanced, so we can
skip detailed UI for it now, but design supports it. - Completion: When the final answer is ready, emit
"message_ready" event with the content.
Implementation-wise, these events could be dispatched via Phoenix.PubSub on topics like
"thread:#{thread_id}" or "agent:#{agent_id}" . Our LiveView for the thread can subscribe to
"thread:#{thread_id}" in mount , and then handle incoming %{event: "message_ready",
data: ...} to append the message. Similarly, the Telegram module might not subscribe (since it's not a
process waiting), but we can directly call the Telegram sending function once we have the final text. For
that, the pipeline stage itself can call a function if source == :telegram . We might unify this by still
using PubSub: have a dedicated subscriber process for Telegram responses. For example, a process could
subscribe to all events with source=telegram and do the API calls. However, since it's single-user and
simpler, an immediate call is fine in this case.
The processing itself uses the agent’s settings to call the LLM. As described in the Agents section, the stage
will assemble the conversation history and call ReqLLM.generate_text or stream_text with tools.
We will handle errors (if the LLM API fails or times out, catch the error and emit an "error" event to notify
the user). We can also implement basic retry or fallback logic here (e.g. if local LLM is overloaded, maybe try
a smaller model or an online API if configured – out of scope for now, but something to note). After
receiving the LLM’s response, we save the response as a new Message in the database (role: agent,
agent_id: that agent). This is important to persist the conversation. Then we emit the "message_ready"
event with the content and the message ID.
1.
Consumer – Outbound Dispatch: The final stage is actually the end of the pipeline: sending the
result out to the user and any cleanup. If we use PubSub events as above, the LiveView and Telegram
have what they need. But we can also have an explicit GenStage consumer that subscribes to the
producer-consumer stage. For instance, MyApp.DispatchConsumer could subscribe and receive
completed messages or events, and then do the sending. In practice, since sending to LiveView is
just a broadcast (which could be done from the stage itself), and sending to Telegram is an HTTP call
(which we could also do immediately), we might not need a separate stage. We could merge this
with the producer-consumer stage for simplicity (i.e., the stage that gets the LLM answer can directly
dispatch it). However, separating concerns can be nice: the middle stage focuses on AI logic, the final
stage focuses on delivering output. If we foresee adding more channels (Slack, etc.), a dispatch stage
could have multiple handlers. For now, we'll implement dispatch in the same stage for fewer moving
parts but keep the code modular (like calling a Notifier.notify(message) that inside checks
the channel and does the right thing – this function acts like the consumer).
11
Threading and Concurrency: By using GenStage, we inherently get back-pressure and concurrency
control 23 24
. For example, we might configure the agent stage to only handle 1 message at a time per
agent (ensuring conversation order), but allow 2 different agents to respond concurrently if needed (so
concurrency equal to number of distinct agent processes free). If using tasks internally, we must be careful
not to break ordering guarantees. GenStage will ensure events are processed in the order they are
demanded. We will likely set max_demand to 1 for the consumer stage if we want strict sequential
processing. But then if we have one consumer for all agents, that serializes across agents too. So instead,
we might spin up one consumer per agent indeed. Perhaps simpler: since the number of agents is small,
we can start a separate pipeline for each agent: e.g. one GenStage producer for all messages and N
consumers (each filter agent). One way: In the producer’s handle_demand , you can choose which events
to send to which consumer if you tag them. Alternatively, spawn one GenStage pipeline per agent
dynamically when an agent is created (this might be complex). Given time, I'll propose a simpler design: we
don't attempt to process two messages truly simultaneously; the user likely interacts with one thread at a
time. If they do switch agents rapidly, those requests will queue and be handled sequentially. The system
can still respond concurrently to different input sources (like if a Telegram message came while a LiveView
one is processing, they might be the same user so not likely simultaneous).
Lifecycle Event Example: Suppose the user on the web asks a question. The flow:
- LiveView calls gateway, gateway enqueues message (and broadcasts a "started" event right after DB
insert). LiveView receives it (or it already showed spinner). Also gateway triggers Telegram typing if source
was Telegram.
- GenStage consumer picks it up, broadcasts maybe "agent_thinking" event (could be same as started or a
second one).
- If the agent uses a tool, we could broadcast "agent_used_tool" with some info. (This could also be logged
to admin console only.)
- When answer is ready, save to DB and broadcast "message_ready" with content and message id. LiveView
receives it and renders the message; Telegram dispatch function sends it as a message via API.
•
If an error occurs (exception from LLM API), broadcast "error" event. The LiveView can show an error
message (and allow retry), Telegram bot can send a sorry message.
This publish/subscribe mechanism decouples UI updates from the core logic. Phoenix PubSub is perfect for
this and works locally (single node) easily. Each thread can be a topic, or each user session could be a topic.
We'll use thread topics so that if in future multiple users or multiple threads open in UI simultaneously, only
the relevant LiveView gets the message.
Why GenStage? This design ensures that heavy LLM calls don’t block the web server. The LiveView process
just enqueues the message and returns, keeping the UI snappy. The GenStage pipeline in the background
does the work. We can adjust the degree of parallelism by tuning the number of consumers or using
Task.Supervisor for tool calls, etc. This pipeline pattern is common for data processing in Elixir 1
and fits
our needs for an AI message workflow.
Additionally, using a GenStage (or Broadway) pipeline opens the door to scaling out or distributing work if
needed (for example, multiple GenStage producers on different nodes feeding into a centralized stage, or
vice versa). For now, a single node is fine.
12
LLM Integration with ReqLLM and Llama-Swap
We will integrate with Large Language Models through the ReqLLM library 25 26
. ReqLLM provides a
unified interface to call various LLM providers using Elixir’s Req HTTP client under the hood. Each provider
(OpenAI, Anthropic, etc.) is implemented as a plugin, and ReqLLM supports many models and even custom
endpoints. Some specifics for our use-case:
•
Choosing a Provider/Model: The Agent’s model field will likely be a string that indicates the
provider. For example, "openai:gpt-4" could denote using OpenAI API with GPT-4 model.
"openai:gpt-3.5-turbo" for the cheaper model, or "anthropic:claude-v1" for Anthropic.
ReqLLM can accept strings in the format "provider:model" as seen in the example 27
. We will
also want to support local models. The mention of "llama-swap based completions API" suggests we
plan to use a local service (like llama.cpp or Ollama) that provides an OpenAI-compatible API
endpoint. Llama-Swap is a tool that can route OpenAI API calls to different local models by model
name 28 29
. We can integrate this by configuring ReqLLM or Req to point to a custom API base
URL for OpenAI provider. For instance, if llama-swap runs at http://localhost:8000/v1 , we can
set an environment variable or Req option to use that instead of the real api.openai.com. ReqLLM
likely reads OpenAI API base from OPENAI_BASE_URL or similar if provided. We will ensure our
system is flexible: in dev, perhaps use openAI (with keys), and in production (or for offline) use a local
llama-swap server with no key required.
•
Streaming vs Non-streaming: If possible, we’ll utilize streaming responses for better user
experience (especially on web UI). ReqLLM supports a streaming mode ( stream_text/3 30
etc.) .
With streaming, we would receive chunks of the assistant’s answer as they are generated. Our
pipeline can forward these chunks via events to LiveView to display partial output (like a real-time
typing effect). On Telegram, streaming is less useful (we’d likely accumulate and send one final
message due to chat limitations). To keep initial complexity manageable, we might first implement
non-streaming (wait for full reply, then send). But we will design such that adding streaming later is
straightforward. For example, our pipeline could detect if the channel is LiveView and if streaming is
enabled, then it would emit "token" or "partial_response" events as they come. LiveView would
append text incrementally. This is an enhancement; the plan ensures it's feasible.
•
ReqLLM Tools: As mentioned, we will integrate our Tools with the LLM calls. ReqLLM allows passing
a list of tool definitions to generate_text 27
. We will create those tool definitions at startup or
on the fly (perhaps caching them in an Agent or in the Agent struct). For example, if an agent has a
tool "calculator" enabled, we have a
calculator_tool = ReqLLM.tool(name: "calculator", description: "...",
callback: &MyTools.calc/1) . We feed that in. Tools results could be multi-step, but ReqLLM
handles the loop of tool usage internally (similar to function calling in OpenAI). After the final answer
is obtained, we proceed.
•
Providers and API Keys: We will configure API keys for any external providers. ReqLLM has a
mechanism to set keys, e.g. ReqLLM.put_key(:openai_api_key, "sk-...") . We’ll call that
during app startup if keys are in config. For local llama-swap, if no key is needed or it uses a dummy,
we just ensure ReqLLM calls it appropriately. The nice thing about ReqLLM is that it “standardizes the
13
API calls and responses for LLM providers” 31
backend by changing the model string and key configuration.
, meaning we write code once and can swap out the
•
Error Handling and Logging: We will incorporate robust error handling around LLM calls. If the
HTTP request fails or the model returns an error (e.g. context length error), the GenStage stage
should catch that and emit an error event. We might log the error in the application log and also
show the user a friendly message (and possibly the admin UI could show the error details). Because
this is a single-user tool, transparency is fine (we can show "Error: model failed to respond, please try
again."). Logging should include conversation ID and agent for debugging.
•
Moderation / Filters: If needed, we could incorporate moderation (OpenAI has moderation API, or
we implement our own filters for content). This isn’t explicitly requested, but mention as a future
extension.
In summary, the integration with LLM will allow us to switch between cloud and local easily. For local Llama,
once llama-swap is running (which listens for OpenAI-format requests and routes to a chosen model 32
),
our system just needs to send requests to it. We ensure that by either configuring ReqLLM’s OpenAI base
URL or by treating llama-swap as a separate provider (some forks of ReqLLM might have explicit support for
Ollama or local endpoints as noted in the forum 33
). We will verify the usage by testing with a known local
model.
Putting It All Together (Module Breakdown)
Let's outline the key modules and how they interact:
•
MyAppWeb.Endpoint – the Phoenix endpoint, sets up LiveView socket, etc. Also, it will configure
LiveDashboard for admin (with the generated token requirement).
•
LiveView UIs:
•
•
•
MyAppWeb.Live.ChatLive – handles user chat interface. Mounts with either a new thread or an
existing thread (we can allow a URL like /chat/:thread_id to reopen a thread). It subscribes to
"thread:#{thread_id}" PubSub topic. It displays messages (using Phoenix.LiveView Streams for
efficient rendering of potentially long lists 34 35
). It provides a form for message input, and
handles events for sending messages or forking (if UI has a fork button). On fork event, it calls an
Ash action or context to create the new thread and then redirects the LiveView to that new thread.
MyAppWeb.Live.AgentConfigLive – admin view for configuring agents (and possibly tools
globally). It loads all Agent records (maybe just one initial agent) and all available tools/skills. We
might structure it with each agent in a card, listing toggles. Changing a toggle triggers an event that
updates that agent’s config (calls Ash update). We ensure to give feedback (maybe a flash message
"updated" or disable toggle while saving, etc.). This LiveView might also allow the creation of a new
agent (with a form for name, model, etc.).
We could have other admin views like ThreadsLive if needed to list threads, or integrate that into
ChatLive (e.g. a sidebar in ChatLive that lists all threads and their last message). That might be nice:
the user can select past threads to revisit, similar to ChatGPT UI. For now, we focus on core
functionalities.
14
•
•
•
•
•
•
•
•
•
•
•
•
•
Domain Modules (Ash):
MyApp.Chat.Thread (Ash resource, with attributes and actions as described).
MyApp.Chat.Message (Ash resource).
MyApp.Agents.Agent (Ash resource).
We will group these into Ash domains for organization. For example, define defmodule
MyApp.Chat do use Ash.Domain; resources do resource MyApp.Chat.Thread;
resource MyApp.Chat.Message; end end . Similarly MyApp.Agents domain for Agent. This
36
grouping is mostly for clarity and potential Ash policy scopes .
If we add User, then MyApp.Accounts.User in domain Accounts.
Context/Service Modules (plain Elixir logic):
MyApp.ChatGateway – handles incoming message routing. Likely implemented as the GenStage
Producer or at least containing the interface to enqueue messages. It might encapsulate the
GenStage producer logic. For instance, ChatGateway.start_link/0 starts the producer stage. It
exposes ChatGateway.send_user_message(thread_id, content, agent_id,
source_meta) which does the flow: Ash.create(Message), GenStage.cast to producer. If needed, it
can also broadcast the "user_message" event to the UI (though the LiveView might just add it
without needing a broadcast). Essentially, it’s the entry point for all channels to submit messages.
MyApp.MessageProcessor – could be the GenStage consumer module (the stage that actually
calls LLM). It will implement GenStage callbacks. On handle_events([event], _from,
state) , it will run the LLM call for that event. We might break it down further:
◦
MyApp.AgentManager or AgentRunner – a helper that given an agent and an input,
orchestrates the LLM tool calls using ReqLLM. But this can be inside MessageProcessor.
◦
This module will use functions from MyApp.Agents context to fetch agent config (e.g.
Ash.get!(Agent, id) or we might have cached the agent in the event itself to avoid DB
hit).
◦
It uses MyApp.Agents.Tools and MyApp.Agents.Skills modules which we will have
for managing the actual code of tools/skills.
MyApp.Agents.Tools – defines available tools. Possibly a list or map of tool definitions. Could
also provide a function to get the ReqLLM.tool structs for a given list of tool names. For example,
MyApp.Agents.Tools.all() -> %{"calculator" => ReqLLM.tool(...), "search" =>
ReqLLM.tool(...), ...} . We might initialize these in an application startup task because some
tools might need config (like API keys for search or etc.). This module will also contain the actual
callback implementations (like def calc(%{expression: expr}), do: ... ).
MyApp.Agents.Skills – similar structure: maybe load skill prompts from files at startup. Provide
all() to list available skills (with descriptions if needed), and prompts_for(names) to return
the list of prompt texts for those skill names.
MyApp.Telegram – contains the ExGram Bot module (as shown above) and maybe helper
functions (like send_message/2, indicate_typing/1 ).
Supervisor setup: In application.ex , we’ll start:
15
•
•
•
•
•
•
the Repo (Ash’s data layer if using Ash with Ecto, yes we will have MyApp.Repo configured for
SQLite),
the Endpoint (Phoenix),
the ChatGateway (GenStage producer) process,
the MessageProcessor stage as a consumer (maybe we use GenStage.sync_subscribe connect it to producer with appropriate options), possibly multiple of them if needed,
the Telegram.Bot (ExGram) process,
and maybe a couple of utility processes (like if we use Registry or Agent for tools).
to
If using Broadway instead of raw GenStage, we'd start a Broadway pipeline which internally starts its
producers/consumers. But let's assume manual GenStage: We ensure to subscribe the stages in the right
order on init. We’ll also subscribe LiveView processes to PubSub topics where needed (LiveView does that in
mount).
•
Phoenix PubSub: Already included by Phoenix, we’ll use it for broadcasting thread events. If the
volume is low (single user), PubSub overhead is minimal and fine.
With these modules defined, the system should be structured and maintainable. The Ash resources
encapsulate data logic (and make testing easier because we can create threads/messages via Ash in tests),
the GenStage pipeline handles asynchronous workflow, and LiveView/ExGram cover the presentation layer.
Testing Strategy (Unit and End-to-End)
We will invest in a comprehensive test suite to ensure each part of the architecture works as expected and
that the whole system behaves correctly in user-facing scenarios. The testing approach will cover:
Unit Tests:
- Ash Resource Tests: Using Ash’s built-in test support or just calling the Ash actions directly. For example, test
that we can create a Thread and Message and fetch them. Use an in-memory SQLite sandbox or the SQL
sandbox provided by Phoenix (similar to Ecto’s). Verify validations or defaults (e.g. creating a thread sets
status to :active by default). Test custom actions like fork_thread : create a sample thread with
messages, call the fork action (or function) and then assert the new thread has the expected copied
messages and link to parent. Also test Agent updates: toggling a tool should result in the enabled_tools
37 38
field updating in the database .
•
Tools and Skills: Unit test each tool’s callback. E.g. if we have a Calculator tool, test that calling its
function with a sample input returns correct result. These are plain functions, so easy to test.
Similarly, if skills have any dynamic logic (unlikely, they might just be static text), we can test that
loading from files works (e.g. put a dummy skill file and see if Skills.all() picks it up).
•
Message Pipeline Logic: We can simulate the GenStage pipeline in tests by not running the actual
GenStage (which is harder to control timing for), but by isolating the processing function. For
example, factor out a function MyApp.MessageProcessor.process_message(message) that
does the LLM call and returns a result. In tests, stub the LLM so we don’t call external APIs: we can
use the Mox library to create a behavior for LLM provider and have ReqLLM calls go through our
mock in test. Alternatively, since ReqLLM is well-tested, we might choose to call a live OpenAI with a
dummy key in CI (not ideal), so better to mock. Possibly we can configure ReqLLM to a dummy
16
"echo" provider in test mode. But easier: structure our code such that the actual HTTP call is
abstracted. E.g. have MyApp.LLMProvider module with a chat_completion(messages,
tools, model) function. In production it calls ReqLLM, in tests we implement a fake that returns a
canned answer (like if it sees a question "What is 2+2?" and calculator tool enabled, it might simulate
calling the tool and returning "4"). We can then assert that our pipeline correctly takes that output
and creates a Message.
We will also test the event broadcasting: perhaps using Phoenix.PubSub’s synchronous subscription in tests
(subscribe, send a message through pipeline, wait for broadcast). For instance, use assert_received
{:message_ready, %{content: "Hello"}} after invoking a pipeline. This ensures our lifecycle events
are fired.
•
LiveView Components: We can use Phoenix.LiveViewTest to test the LiveViews. For example,
mount the ChatLive with a known thread (seed some messages using Ash in setup), ensure it
renders those messages. Simulate the user sending a message: use render_submit(form, %
{content: "Hi"}) and then intercept the message that would be sent. We might need to
temporarily configure the pipeline to bypass actual LLM for test (we could set agent to a special
"EchoAgent" that simply echoes input via a stubbed pipeline). Alternatively, we can test ChatLive in
isolation by mocking ChatGateway. For instance, have ChatGateway in test mode just broadcast a
fake response immediately. LiveView tests can subscribe to PubSub and then we push an event to
simulate pipeline finishing. Then we can verify the rendered HTML contains the response.
Similarly, test the AgentConfigLive: mount it with an agent in the database (create one in setup with some
tools disabled). Ensure the checkboxes reflect the DB state. Simulate clicking a toggle (using
render_click on the toggle element) and then verify that the Agent’s record in DB updated accordingly
(and maybe that the UI shows a flash or updated state). We can also test that adding a new agent via a form
works if we implement that.
Integration / End-to-End Tests:
For end-to-end testing, one level is testing the GenStage pipeline integrated with the UIs:
•
Web E2E: Launch a LiveView client (maybe headless via Wallaby or just LiveViewTest) that goes
through an entire conversation: user enters a question, the pipeline yields an answer, and the UI
updates. This is tricky without a real LLM. We likely use a dummy agent (in tests only) where instead
of calling an external LLM, we substitute a deterministic function. One approach: configure the
agent’s model to something like "echo:test" and make our LLMProvider handle that by simply
returning the user question reversed or something. Then the test can predict what the answer
should be. For example: content "Hello" leads to answer "Echo: Hello". Then assert the LiveView
shows "Echo: Hello". This confirms the whole loop from UI to DB to pipeline to UI.
•
Telegram E2E: We can simulate a Telegram update by calling our ExGram bot’s handle/2 function
directly in tests (since it’s just a module function). Provide a fake context and message, then after a
short delay, verify that a message was sent via our Telegram sending mechanism. We might capture
outgoing HTTP requests by using a test HTTP client (for Req, perhaps set a flag to not actually post
but instead record the payload). If using ExGram’s answer, we could spy on ExGram module with
Mox. Alternatively, simpler: structure Telegram sending through a MyApp.Telegram behaviour
17
that we mock in test. Then ensure after processing, chat_id and text.
MyApp.Telegram was called with expected
•
Concurrent scenario test: Create two different threads with two different agents. Simulate sending a
message to each in quick succession. Assert that both get responses and that the order of responses
is correct (ideally, they might run in parallel, so any order is fine or maybe the one started first
returns first; we ensure no cross-talk or crashes). This tests isolation of the pipeline per thread/
agent.
Performance and Load Testing: Not a primary focus for functionality, but we could write a simple
benchmark test that sends a batch of messages sequentially through the pipeline (with a stubbed fast LLM)
to measure throughput and ensure GenStage back-pressure works (e.g. if we flood 10 messages, does it
queue properly). If we had multi-user, we’d test that one user’s long-running query doesn’t block another’s
short query (with our design it shouldn’t if different agents or threads, but currently single user so moot).
Docker sandbox test: If we incorporate any sandbox or external process (not initially, but say we do for
code execution), we would test that the system can invoke it. Possibly an integration test that actually runs a
tiny Docker container to execute 2+2 and returns 4, verifying that path. But since it's out-of-scope now, we
skip.
Throughout testing, we will use the SQL sandbox to rollback DB changes between tests. Ash works with
Ecto SQL sandbox similarly to normal Ecto, so we set that up in test support.
By covering unit tests of each piece and a few end-to-end flows, we can be confident the architecture is
correct. The test suite will double as documentation of how the system is supposed to behave for future
developers (including “Ralph Wiggum” level developers – the tests will show example usage).
Conclusion and Future Considerations
This architecture brings together Phoenix LiveView for an interactive UI, Ash for robust domain modeling,
and GenStage for concurrent processing – leveraging the strengths of Elixir’s BEAM for an “agentic” AI
system 39 40
. The design is modular: new channels can be added by plugging into the gateway, new
tools/skills can be added by writing an Elixir function or prompt file, and new agents can be configured
without code changes.
We addressed all the requirements (LiveView UIs, Telegram integration, generic gateway, threads with
forking, GenStage events, agent config UI, ReqLLM with llama integration) in the design. If anything was
missed: - We assumed a single user scenario, so we did not implement multi-user authentication beyond
the admin token. In future, adding a User resource and tying threads to users would be needed. - We
should note security: validate user input (to avoid injection in prompts maybe, though prompt injection is a
known hard problem – perhaps out of scope to solve completely, but we could at least sanitize inputs if
needed). Also ensure the Phoenix endpoint has proper check for the admin token on sensitive routes. -
Monitoring: We might want to log usage stats (how many tokens used, etc.). ReqLLM provides usage
metadata for cost tracking 41
which we could log or display. - Ensure that shutting down the system
handles any in-progress tasks (GenStage will terminate consumers; we might implement a graceful stop to
finish LLM calls or simply let them drop).
18
All things considered, this plan should be something a developer can follow step-by-step to implement the
system. It balances leveraging high-level frameworks (Ash, LiveView, ReqLLM) with lower-level control
(GenStage pipeline) to achieve a powerful, extensible AI chat platform. Each module and component has a
clear responsibility, and we’ve outlined how to test them to guarantee it “just works” when put together.
Sources: The architectural concepts and examples are informed by recent practices in Elixir and LLM
integration, such as Ash Framework for conversation modeling 11 37 1
, using GenStage for pipelines ,
and ReqLLM for tool-enabled LLM calls 19
. These provide confidence that our design is rooted in proven
approaches while tailored to the specific needs of this system.
1 20 23 24
GenStage · Elixir School
https://elixirschool.com/en/lessons/data_processing/genstage
2 3 34 35
Building a Chat App with LiveView Streams · The Phoenix Files
https://fly.io/phoenix-files/building-a-chat-app-with-liveview-streams/
4 5 8 9 10 11 12 13 14 15 16 17 18 36 37 38
Domains and Resources in Ash for Elixir |
AppSignal Blog
https://blog.appsignal.com/2026/01/13/domains-and-resources-in-ash-for-elixir.html
6 7
telegram-bots-with-exgram
https://ironjanowar.github.io/blog/telegram-bots-with-exgram/
19 25 26 27 30 33 41
ReqLLM - Composable LLM client built on Req - Libraries - Elixir Programming
Language Forum
https://elixirforum.com/t/reqllm-composable-llm-client-built-on-req/72514
21 22
Need Help: GenStage - Recording Messages To Database & Handle Database Downtime Situations -
Questions / Help - Elixir Programming Language Forum
https://elixirforum.com/t/need-help-genstage-recording-messages-to-database-handle-database-downtime-situations/44446
28 32
How to Run Multiple LLMs Locally Using Llama-Swap on a Single ...
https://www.kdnuggets.com/how-to-run-multiple-llms-locally-using-llama-swap-on-a-single-server
29
My Journey with llama-swap: Revolutionizing Local LLM Management
https://medium.com/@learn-simplified/my-journey-with-llama-swap-revolutionizing-local-llm-management-c3fd0f788d36
31
Overview — ReqLLM v1.2.0 - Hexdocs
https://hexdocs.pm/req_llm/
39 40
Integrating Generative AI into Elixir-based applications by using the Jido agentic framework |
Appunite
https://www.appunite.com/blog/integrating-generative-ai-into-elixir-based-applications-by-using-the-jido-agentic-framework
19
