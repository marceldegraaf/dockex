defmodule Dockex.Decoder.JsonStream do

  def start(identifier, target_pid, event_name_prefix \\ "json") do
    Task.start(fn -> receive_json_stream(identifier, target_pid, event_name_prefix) end)
  end

  def receive_json_stream(identifier, target_pid, event_name_prefix) do
    receive do
      %HTTPoison.AsyncChunk{chunk: chunk} ->
        payload = Poison.decode!(chunk)

        send target_pid, %Dockex.Client.AsyncReply{event: "#{event_name_prefix}_stream_data", payload: payload, topic: identifier}

        receive_json_stream(identifier, target_pid, event_name_prefix)

      %HTTPoison.AsyncEnd{} ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "#{event_name_prefix}_stream_end", topic: identifier}

      :close ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "#{event_name_prefix}_stream_end", topic: identifier}
    end
  end

end
