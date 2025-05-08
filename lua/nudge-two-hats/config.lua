local config = {
  system_prompt = "Give a 10-character advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  execution_delay = 3000, -- Delay in milliseconds
  gemini_model = "gemini-2.0-flash", -- Using Gemini 2.0 Flash as recommended
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent",
}

return config
