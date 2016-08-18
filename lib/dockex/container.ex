defmodule Dockex.Container do
  defstruct id: nil,
            name: nil,
            cmd: [],
            env: [],
            image: nil,
            attach_stdin: false,
            attach_stdout: false,
            attach_stderr: false
end
