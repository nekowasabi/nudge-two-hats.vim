local config = {
  system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  
  filetype_prompts = {
    markdown = "Give advice about this writing, focusing on clarity and structure.",
    text = "Give advice about this writing, focusing on clarity and structure.",
    tex = "Give advice about this LaTeX document, focusing on structure and formatting.",
    rst = "Give advice about this reStructuredText document, focusing on clarity and organization.",
    org = "Give advice about this Org document, focusing on organization and structure.",
    
    lua = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
    python = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
    javascript = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  },
  
  message_length = 10, -- Default length of the advice message
  length_type = "characters", -- Can be "characters" or "words"
  
  output_language = "auto", -- Can be "auto", "en" (English), or "ja" (Japanese)
  translate_messages = true, -- Whether to translate messages to the specified language
  
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  min_interval = 60, -- Minimum interval between API calls in seconds
  
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
}

return config
