defmodule Piano.Codex.CommandsTest do
  use ExUnit.Case, async: true

  alias Piano.Codex.Commands

  describe "SandboxPolicy" do
    test "new/1 creates with defaults" do
      policy = Commands.SandboxPolicy.new()
      assert policy.type == :workspace_write
      assert policy.writable_roots == nil
      assert policy.network_access == true
    end

    test "new/1 accepts options" do
      policy =
        Commands.SandboxPolicy.new(
          type: :read_only,
          writable_roots: ["/tmp"],
          network_access: false
        )

      assert policy.type == :read_only
      assert policy.writable_roots == ["/tmp"]
      assert policy.network_access == false
    end

    test "to_map/1 serializes correctly" do
      policy = Commands.SandboxPolicy.new(type: :workspace_write)
      map = Commands.SandboxPolicy.to_map(policy)

      assert map["type"] == "workspaceWrite"
      assert map["networkAccess"] == true
    end

    test "to_map/1 omits nil writable_roots" do
      policy = Commands.SandboxPolicy.new()
      map = Commands.SandboxPolicy.to_map(policy)

      refute Map.has_key?(map, "writableRoots")
    end

    test "to_map/1 serializes all types correctly" do
      assert Commands.SandboxPolicy.to_map(%Commands.SandboxPolicy{type: :read_only})["type"] ==
               "readOnly"

      assert Commands.SandboxPolicy.to_map(%Commands.SandboxPolicy{type: :full_access})["type"] ==
               "fullAccess"
    end
  end

  describe "InputItem" do
    test "text/1 creates text item" do
      item = Commands.InputItem.text("Hello")
      assert item.type == :text
      assert item.text == "Hello"
    end

    test "image/1 creates image item" do
      item = Commands.InputItem.image("https://example.com/img.png")
      assert item.type == :image
      assert item.url == "https://example.com/img.png"
    end

    test "local_image/1 creates local image item" do
      item = Commands.InputItem.local_image("/tmp/img.png")
      assert item.type == :local_image
      assert item.path == "/tmp/img.png"
    end

    test "skill/2 creates skill item" do
      item = Commands.InputItem.skill("my-skill", "/path/to/skill.md")
      assert item.type == :skill
      assert item.name == "my-skill"
      assert item.path == "/path/to/skill.md"
    end

    test "to_map/1 serializes text item" do
      item = Commands.InputItem.text("Hello")
      assert Commands.InputItem.to_map(item) == %{"type" => "text", "text" => "Hello"}
    end

    test "to_map/1 serializes image item" do
      item = Commands.InputItem.image("https://example.com/img.png")
      assert Commands.InputItem.to_map(item) == %{"type" => "image", "url" => "https://example.com/img.png"}
    end

    test "to_map/1 serializes local image item" do
      item = Commands.InputItem.local_image("/tmp/img.png")
      assert Commands.InputItem.to_map(item) == %{"type" => "localImage", "path" => "/tmp/img.png"}
    end

    test "to_map/1 serializes skill item" do
      item = Commands.InputItem.skill("my-skill", "/path/to/skill.md")
      assert Commands.InputItem.to_map(item) == %{
               "type" => "skill",
               "name" => "my-skill",
               "path" => "/path/to/skill.md"
             }
    end
  end

  describe "Initialize command" do
    test "new/1 creates with defaults" do
      cmd = Commands.Initialize.new()
      assert cmd.client_info.name == "piano_client"
      assert cmd.client_info.version == "0.1.0"
      assert cmd.client_info.title == nil
      assert cmd.capabilities == nil
    end

    test "new/1 accepts options" do
      cmd =
        Commands.Initialize.new(
          name: "test_client",
          title: "Test Client",
          version: "1.0.0",
          capabilities: %{}
        )

      assert cmd.client_info.name == "test_client"
      assert cmd.client_info.title == "Test Client"
      assert cmd.client_info.version == "1.0.0"
      assert cmd.capabilities == %{}
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.Initialize.new(name: "test", version: "1.0")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "initialize"
      assert json["id"] == 1
      assert json["params"]["clientInfo"]["name"] == "test"
      assert json["params"]["clientInfo"]["version"] == "1.0"
    end

    test "to_json_rpc/1 includes title when present" do
      cmd = Commands.Initialize.new(title: "My Client")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["params"]["clientInfo"]["title"] == "My Client"
    end

    test "to_json_rpc/1 includes capabilities when present" do
      cmd = Commands.Initialize.new(capabilities: %{"feature" => true})
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["params"]["capabilities"] == %{"feature" => true}
    end
  end

  describe "Initialized command" do
    test "new/0 creates command" do
      cmd = Commands.Initialized.new()
      assert %Commands.Initialized{} = cmd
    end

    test "to_json_rpc/1 serializes as notification (no id)" do
      cmd = Commands.Initialized.new()
      json = Commands.to_json_rpc(cmd)

      assert json["method"] == "initialized"
      assert json["params"] == %{}
      refute Map.has_key?(json, "id")
    end
  end

  describe "ThreadStart command" do
    test "new/1 creates with defaults" do
      cmd = Commands.ThreadStart.new()
      assert cmd.model == nil
      assert cmd.input_items == []
    end

    test "new/1 accepts string input" do
      cmd = Commands.ThreadStart.new(input: "Hello world")
      assert length(cmd.input_items) == 1
      assert hd(cmd.input_items).type == :text
      assert hd(cmd.input_items).text == "Hello world"
    end

    test "new/1 accepts list of InputItems" do
      items = [
        Commands.InputItem.text("Hello"),
        Commands.InputItem.image("https://example.com/img.png")
      ]

      cmd = Commands.ThreadStart.new(input: items)
      assert length(cmd.input_items) == 2
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadStart.new(
        model: "gpt-5.1-codex",
        input: "Hello",
        approval_policy: "unlessTrusted"
      )

      json = Commands.to_json_rpc(cmd, request_id: 10)

      assert json["method"] == "thread/start"
      assert json["id"] == 10
      assert json["params"]["model"] == "gpt-5.1-codex"
      assert json["params"]["approvalPolicy"] == "unlessTrusted"
      assert [%{"type" => "text", "text" => "Hello"}] = json["params"]["input"]
    end

    test "to_json_rpc/1 includes sandbox policy" do
      policy = Commands.SandboxPolicy.new(type: :read_only)
      cmd = Commands.ThreadStart.new(sandbox_policy: policy)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["params"]["sandbox"]["type"] == "readOnly"
    end
  end

  describe "ThreadResume command" do
    test "new/1 creates command" do
      cmd = Commands.ThreadResume.new("thr_123")
      assert cmd.thread_id == "thr_123"
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadResume.new("thr_123")
      json = Commands.to_json_rpc(cmd, request_id: 5)

      assert json["method"] == "thread/resume"
      assert json["id"] == 5
      assert json["params"]["threadId"] == "thr_123"
    end
  end

  describe "ThreadFork command" do
    test "new/2 creates with defaults" do
      cmd = Commands.ThreadFork.new("thr_123")
      assert cmd.thread_id == "thr_123"
      assert cmd.turn_id == nil
    end

    test "new/2 accepts turn_id" do
      cmd = Commands.ThreadFork.new("thr_123", turn_id: "turn_456")
      assert cmd.turn_id == "turn_456"
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadFork.new("thr_123", turn_id: "turn_456")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/fork"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["turnId"] == "turn_456"
    end
  end

  describe "ThreadRead command" do
    test "new/2 defaults include_turns to true" do
      cmd = Commands.ThreadRead.new("thr_123")
      assert cmd.include_turns == true
    end

    test "new/2 can disable include_turns" do
      cmd = Commands.ThreadRead.new("thr_123", include_turns: false)
      assert cmd.include_turns == false
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadRead.new("thr_123")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/read"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["includeTurns"] == true
    end
  end

  describe "ThreadList command" do
    test "new/1 creates with defaults" do
      cmd = Commands.ThreadList.new()
      assert cmd.include_archived == false
      assert cmd.cursor == nil
      assert cmd.limit == nil
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadList.new(cursor: "abc", limit: 10, include_archived: true)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/list"
      assert json["params"]["cursor"] == "abc"
      assert json["params"]["limit"] == 10
      assert json["params"]["includeArchived"] == true
    end
  end

  describe "ThreadArchive and ThreadUnarchive commands" do
    test "ThreadArchive.new/1 and serialization" do
      cmd = Commands.ThreadArchive.new("thr_123")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/archive"
      assert json["params"]["threadId"] == "thr_123"
    end

    test "ThreadUnarchive.new/1 and serialization" do
      cmd = Commands.ThreadUnarchive.new("thr_123")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/unarchive"
      assert json["params"]["threadId"] == "thr_123"
    end
  end

  describe "ThreadRollback command" do
    test "new/2 creates command" do
      cmd = Commands.ThreadRollback.new("thr_123", 5)
      assert cmd.thread_id == "thr_123"
      assert cmd.num_turns == 5
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ThreadRollback.new("thr_123", 3)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "thread/rollback"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["numTurns"] == 3
    end
  end

  describe "TurnStart command" do
    test "new/2 creates with required fields" do
      cmd = Commands.TurnStart.new("thr_123", input: "Hello")
      assert cmd.thread_id == "thr_123"
      assert length(cmd.input_items) == 1
    end

    test "new/2 accepts list of InputItems" do
      items = [
        Commands.InputItem.text("Hello"),
        Commands.InputItem.skill("my-skill", "/path/to/skill.md")
      ]

      cmd = Commands.TurnStart.new("thr_123", input: items, model: "gpt-4")
      assert length(cmd.input_items) == 2
      assert cmd.model == "gpt-4"
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.TurnStart.new("thr_123",
        input: "Hello",
        model: "gpt-5.1-codex",
        effort: "high"
      )

      json = Commands.to_json_rpc(cmd, request_id: 30)

      assert json["method"] == "turn/start"
      assert json["id"] == 30
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["model"] == "gpt-5.1-codex"
      assert json["params"]["effort"] == "high"
      assert [%{"type" => "text"}] = json["params"]["input"]
    end
  end

  describe "TurnInterrupt command" do
    test "new/2 creates command" do
      cmd = Commands.TurnInterrupt.new("thr_123", "turn_456")
      assert cmd.thread_id == "thr_123"
      assert cmd.turn_id == "turn_456"
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.TurnInterrupt.new("thr_123", "turn_456")
      json = Commands.to_json_rpc(cmd, request_id: 31)

      assert json["method"] == "turn/interrupt"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["turnId"] == "turn_456"
    end
  end

  describe "CommandExec command" do
    test "new/2 creates with defaults" do
      cmd = Commands.CommandExec.new(["ls", "-la"])
      assert cmd.command == ["ls", "-la"]
      assert cmd.cwd == nil
    end

    test "new/2 accepts options" do
      policy = Commands.SandboxPolicy.new()

      cmd =
        Commands.CommandExec.new(["pwd"],
          cwd: "/tmp",
          sandbox_policy: policy,
          timeout_ms: 5000
        )

      assert cmd.cwd == "/tmp"
      assert cmd.sandbox_policy == policy
      assert cmd.timeout_ms == 5000
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.CommandExec.new(["ls", "-la"], cwd: "/tmp")
      json = Commands.to_json_rpc(cmd, request_id: 50)

      assert json["method"] == "command/exec"
      assert json["params"]["command"] == ["ls", "-la"]
      assert json["params"]["cwd"] == "/tmp"
    end
  end

  describe "Account commands" do
    test "AccountRead.new/1 and serialization" do
      cmd = Commands.AccountRead.new(refresh_token: true)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "account/read"
      assert json["params"]["refreshToken"] == true
    end

    test "AccountLoginStart.new/2 for api_key" do
      cmd = Commands.AccountLoginStart.new(:api_key, api_key: "sk-123")
      json = Commands.to_json_rpc(cmd, request_id: 2)

      assert json["method"] == "account/login/start"
      assert json["params"]["type"] == "apiKey"
      assert json["params"]["apiKey"] == "sk-123"
    end

    test "AccountLoginStart.new/2 for chatgpt" do
      cmd = Commands.AccountLoginStart.new(:chatgpt)
      json = Commands.to_json_rpc(cmd, request_id: 3)

      assert json["method"] == "account/login/start"
      assert json["params"]["type"] == "chatgpt"
      refute Map.has_key?(json["params"], "apiKey")
    end

    test "AccountLoginCancel.new/1 and serialization" do
      cmd = Commands.AccountLoginCancel.new("login_123")
      json = Commands.to_json_rpc(cmd, request_id: 4)

      assert json["method"] == "account/login/cancel"
      assert json["params"]["loginId"] == "login_123"
    end

    test "AccountLogout.new/0 and serialization" do
      cmd = Commands.AccountLogout.new()
      json = Commands.to_json_rpc(cmd, request_id: 5)

      assert json["method"] == "account/logout"
    end

    test "AccountRateLimitsRead.new/0 and serialization" do
      cmd = Commands.AccountRateLimitsRead.new()
      json = Commands.to_json_rpc(cmd, request_id: 6)

      assert json["method"] == "account/rateLimits/read"
    end
  end

  describe "Config commands" do
    test "ConfigRead.new/0 and serialization" do
      cmd = Commands.ConfigRead.new()
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "config/read"
    end

    test "ConfigValueWrite.new/2 and serialization" do
      cmd = Commands.ConfigValueWrite.new("model", "gpt-4")
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "config/value/write"
      assert json["params"]["key"] == "model"
      assert json["params"]["value"] == "gpt-4"
    end
  end

  describe "Skills commands" do
    test "SkillsList.new/1 and serialization" do
      cmd = Commands.SkillsList.new(cwds: ["/home/project"], force_reload: true)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "skills/list"
      assert json["params"]["cwds"] == ["/home/project"]
      assert json["params"]["forceReload"] == true
    end

    test "SkillsConfigWrite.new/2 and serialization" do
      cmd = Commands.SkillsConfigWrite.new("/path/to/skill.md", false)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "skills/config/write"
      assert json["params"]["path"] == "/path/to/skill.md"
      assert json["params"]["enabled"] == false
    end
  end

  describe "ReviewStart command" do
    test "new/2 with default options" do
      cmd = Commands.ReviewStart.new("thr_123")
      assert cmd.thread_id == "thr_123"
      assert cmd.target == :uncommitted_changes
      assert cmd.delivery == :inline
    end

    test "new/2 with custom options" do
      cmd = Commands.ReviewStart.new("thr_123", target: :base_branch, delivery: :detached)
      assert cmd.target == :base_branch
      assert cmd.delivery == :detached
    end

    test "new/2 with custom target" do
      cmd = Commands.ReviewStart.new("thr_123", target: {:custom, "main"})
      assert cmd.target == {:custom, "main"}
    end

    test "to_json_rpc/1 serializes correctly" do
      cmd = Commands.ReviewStart.new("thr_123", target: :base_branch, delivery: :detached)
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["method"] == "review/start"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["target"] == "baseBranch"
      assert json["params"]["delivery"] == "detached"
    end

    test "to_json_rpc/1 handles custom target" do
      cmd = Commands.ReviewStart.new("thr_123", target: {:custom, "feature-branch"})
      json = Commands.to_json_rpc(cmd, request_id: 1)

      assert json["params"]["target"] == "feature-branch"
    end
  end

  describe "Convenience functions" do
    test "thread_start/1 creates request" do
      json = Commands.thread_start(model: "gpt-4", input: "Hello", request_id: 1)

      assert json["method"] == "thread/start"
      assert json["id"] == 1
      assert json["params"]["model"] == "gpt-4"
    end

    test "turn_start/2 creates request" do
      json = Commands.turn_start("thr_123", input: "Hello", model: "gpt-4", request_id: 30)

      assert json["method"] == "turn/start"
      assert json["id"] == 30
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["model"] == "gpt-4"
    end

    test "thread_read/2 creates request" do
      json = Commands.thread_read("thr_123", request_id: 1, include_turns: false)

      assert json["method"] == "thread/read"
      assert json["params"]["threadId"] == "thr_123"
      assert json["params"]["includeTurns"] == false
    end

    test "initialize/1 creates request" do
      json = Commands.initialize(name: "test", request_id: 0)

      assert json["method"] == "initialize"
      assert json["id"] == 0
      assert json["params"]["clientInfo"]["name"] == "test"
    end

    test "initialized/0 creates notification" do
      json = Commands.initialized()

      assert json["method"] == "initialized"
      refute Map.has_key?(json, "id")
    end

    test "account_read/1 creates request" do
      json = Commands.account_read(refresh_token: true, request_id: 1)

      assert json["method"] == "account/read"
      assert json["params"]["refreshToken"] == true
    end
  end
end
