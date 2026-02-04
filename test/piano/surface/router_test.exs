defmodule Piano.Surface.RouterTest do
  use ExUnit.Case, async: true

  alias Piano.Surface.Router
  alias Piano.Mock.Surface, as: MockSurface
  alias Piano.Telegram.Surface, as: TelegramSurface

  describe "parse/1" do
    test "parses telegram reply_to" do
      assert {:ok, %TelegramSurface{chat_id: 123456, message_id: 789}} =
               Router.parse("telegram:123456:789")
    end

    test "parses mock reply_to" do
      assert {:ok, %MockSurface{mock_id: "test-123"}} =
               Router.parse("mock:test-123")
    end

    test "returns placeholder for liveview" do
      assert {:ok, :liveview_not_implemented} = Router.parse("liveview:session-123")
    end

    test "returns error for unknown format" do
      assert :error = Router.parse("unknown:foo")
      assert :error = Router.parse("invalid")
    end
  end

  describe "app_type/1" do
    test "identifies telegram" do
      assert :telegram = Router.app_type("telegram:123:456")
    end

    test "identifies mock" do
      assert :mock = Router.app_type("mock:test")
    end

    test "identifies liveview" do
      assert :liveview = Router.app_type("liveview:session")
    end

    test "returns unknown for unrecognized" do
      assert :unknown = Router.app_type("foo:bar")
    end
  end

  describe "base_identifier/1" do
    test "extracts telegram chat_id" do
      assert "123456" = Router.base_identifier("telegram:123456:789")
      assert "-100123" = Router.base_identifier("telegram:-100123:789")
    end

    test "extracts mock_id" do
      assert "test-uuid" = Router.base_identifier("mock:test-uuid")
    end

    test "extracts liveview session_id" do
      assert "session-123" = Router.base_identifier("liveview:session-123")
    end

    test "returns nil for unknown" do
      assert nil == Router.base_identifier("unknown:foo")
    end
  end

  describe "single_user?/1" do
    test "telegram DM (positive chat_id) is single-user" do
      assert Router.single_user?("telegram:123456:789")
    end

    test "telegram group (negative chat_id) is multi-user" do
      refute Router.single_user?("telegram:-100123456:789")
    end

    test "mock is always single-user" do
      assert Router.single_user?("mock:test-123")
    end

    test "liveview is always single-user" do
      assert Router.single_user?("liveview:session")
    end
  end
end
