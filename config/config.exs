import Config

config :plato,
  tick_interval_ms: 1000,
  history_size: 50,
  default_alarm_cooldown: 5

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
