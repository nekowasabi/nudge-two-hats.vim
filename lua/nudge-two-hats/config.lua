local config = {
  system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  
  default_cbt = {
    role = "Cognitive behavioral therapy specialist",
    direction = "Guide towards healthier thought patterns and behaviors",
    emotion = "Empathetic and understanding",
    tone = "Supportive and encouraging but direct",
    hats = {"Therapist", "Coach", "Mentor", "Advisor", "Counselor"},
  },
  
  filetype_prompts = {
    markdown = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing", 
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Writing Coach", "Editor", "Reviewer", "Content Specialist", "Clarity Expert"},
    },
    text = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Writing Coach", "Editor", "Reviewer", "Content Specialist", "Clarity Expert"},
    },
    tex = {
      prompt = "Give advice about this LaTeX document, focusing on structure and formatting.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards well-formatted and structured document",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"LaTeX Expert", "Document Formatter", "Structure Specialist", "Academic Advisor", "Technical Writer"},
    },
    rst = {
      prompt = "Give advice about this reStructuredText document, focusing on clarity and organization.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more organized documentation",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Documentation Expert", "Structure Advisor", "Clarity Coach", "Technical Writer", "Information Architect"},
    },
    org = {
      prompt = "Give advice about this Org document, focusing on organization and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards better organized and structured document",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Organization Expert", "Structure Advisor", "Productivity Coach", "Planning Specialist", "Task Manager"},
    },
    
    lua = {
      prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Code Reviewer", "Refactoring Expert", "Clean Code Advocate", "Performance Optimizer", "Maintainability Advisor"},
    },
    python = {
      prompt = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Python Expert", "Code Reviewer", "Clean Code Advocate", "Performance Optimizer", "Pythonic Style Guide"},
    },
    javascript = {
      prompt = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"JavaScript Expert", "Frontend Advisor", "Code Quality Advocate", "Performance Guru", "Best Practices Guide"},
    },
  },
  
  message_length = 10, -- Default length of the advice message
  length_type = "characters", -- Can be "characters" or "words"
  
  output_language = "auto", -- Can be "auto", "en" (English), or "ja" (Japanese)
  translate_messages = true, -- Whether to translate messages to the specified language
  
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  min_interval = 1, -- Minimum interval between API calls in minutes
  
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
}

return config
