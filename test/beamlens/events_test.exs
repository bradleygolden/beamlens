defmodule Beamlens.EventsTest do
  use ExUnit.Case, async: true

  alias Beamlens.Events.{JudgeCall, LLMCall, ToolCall}

  describe "Events module" do
    test "exports all event struct modules" do
      assert Code.ensure_loaded?(LLMCall)
      assert Code.ensure_loaded?(ToolCall)
      assert Code.ensure_loaded?(JudgeCall)
    end

    test "event structs can be created" do
      llm_call = %LLMCall{
        occurred_at: DateTime.utc_now(),
        iteration: 0,
        tool_selected: "get_overview"
      }

      tool_call = %ToolCall{
        occurred_at: DateTime.utc_now(),
        intent: "get_overview",
        result: %{}
      }

      judge_call = %JudgeCall{
        occurred_at: DateTime.utc_now(),
        attempt: 1,
        verdict: :accept,
        confidence: :high,
        issues: [],
        feedback: ""
      }

      assert %LLMCall{} = llm_call
      assert %ToolCall{} = tool_call
      assert %JudgeCall{} = judge_call
    end
  end
end
