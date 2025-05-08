local config = {
  system_prompt = "Give a 10-character advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  min_interval = 60, -- Minimum interval between API calls in seconds
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
}

return config
