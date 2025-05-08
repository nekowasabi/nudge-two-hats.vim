local config = {
  system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  
  default_cbt = {
    role = "Cognitive behavioral therapy specialist",
    direction = "Guide towards healthier thought patterns and behaviors",
    emotion = "Empathetic and understanding",
    tone = "Supportive and encouraging but direct",
  },
  
  filetype_prompts = {
    markdown = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing", 
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    text = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    tex = {
      prompt = "Give advice about this LaTeX document, focusing on structure and formatting.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards well-formatted and structured document",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    rst = {
      prompt = "Give advice about this reStructuredText document, focusing on clarity and organization.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more organized documentation",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    org = {
      prompt = "Give advice about this Org document, focusing on organization and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards better organized and structured document",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    
    lua = {
      prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    python = {
      prompt = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    javascript = {
      prompt = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
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
