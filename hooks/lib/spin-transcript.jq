# Present Codex rollout records in the conversation format used by spin-check.
select(.type == "response_item") | .payload
| if .type == "message" and (.role == "user" or .role == "assistant") then
    {type: .role, message: {content: [.content[]?
      | select(.type == "input_text" or .type == "output_text")
      | {type: "text", text: .text}]}}
  elif .type == "function_call" or .type == "custom_tool_call" then
    (.arguments // .input // "") as $raw
    | (try ($raw | fromjson) catch {command: $raw}) as $args
    | {type: "assistant", message: {content: [{type: "tool_use",
        name: (if (.name | endswith("spawn_agent")) then "Agent" else .name end),
        input: ($args + {prompt: ($args.prompt // $args.message // "")})}]}}
  else empty end
