import Config

# Logger metadata keys used by BeamLens for tracing
config :logger, :default_handler, metadata: [:trace_id, :tool_name, :tool_count]

import_config "#{config_env()}.exs"
