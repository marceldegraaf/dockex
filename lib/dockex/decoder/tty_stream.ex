defmodule Dockex.Decoder.TtyStream do

  def start(identifier, target_pid, event_name_prefix) do
    Task.start(fn -> receive_tty_stream(identifier, target_pid, event_name_prefix) end)
  end

  def receive_tty_stream(identifier, target_pid, event_name_prefix) do
    receive do
      %HTTPoison.AsyncChunk{chunk: chunk} ->
        payload = case decode_stream(chunk, []) do
          {[], rest} -> %{result: rest, stream_type: ""}
          {[stdin: line], _rest} -> %{result: line, stream_type: "stdin"}
          {[stdout: line], _rest} -> %{result: line, stream_type: "stdout"}
          {[stderr: line], _rest} -> %{result: line, stream_type: "stderr"}
        end

        send target_pid, %Dockex.Client.AsyncReply{event: "#{event_name_prefix}_stream_data", payload: payload, topic: identifier}

        receive_tty_stream(identifier, target_pid, event_name_prefix)

      %HTTPoison.AsyncEnd{} ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "#{event_name_prefix}_stream_end", topic: identifier}

      :close ->
        send target_pid, %Dockex.Client.AsyncEnd{event: "#{event_name_prefix}_stream_end", topic: identifier}
    end
  end

  def decode_stream(<<type, 0 ,0, 0, size :: integer-big-size(32), rest :: binary>> = packet, acc) do
    if size <= byte_size(rest) do
      <<data :: binary-size(size), rest0 :: binary>> = rest

      type = case type do
        0 -> :stdin
        1 -> :stdout
        2 -> :stderr
        other -> other
      end

      acc = [ { type, data } | acc ]

      decode_stream(rest0, acc)
    else
     { Enum.reverse(acc), packet }
    end
  end
  def decode_stream(packet, acc) when byte_size(packet) < 8 do
    { Enum.reverse(acc), packet }
  end
  def decode_stream(_packet, _acc), do: raise ArgumentError

end
