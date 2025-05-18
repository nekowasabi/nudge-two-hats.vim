local config = {
  system_prompt = "Analyze this code change and provide varied, specific advice based on the actual diff content. Consider whether the programmer is focusing on refactoring, adding new features, fixing bugs, or improving tests. Your advice should be tailored to the specific changes you see in the diff and should vary in content and style each time.",
  purpose = "", -- Work purpose or objective (e.g., "code review", "refactoring", "feature development")
  
  translations = {
    en = {
      enabled = "enabled",
      disabled = "disabled",
      api_key_set = "Gemini API key set",
      started_buffer = "Nudge Two Hats started for current buffer",
      debug_enabled = "Debug mode enabled - nudge text will be printed to :messages",
      no_changes = "No changes detected to generate advice",
      api_key_not_set = "Gemini API key not set. Set GEMINI_API_KEY environment variable or use :NudgeTwoHatsSetApiKey to set it.",
      api_error = "Gemini API error",
      unknown_error = "Unknown error",
    },
    ja = {
      enabled = "有効",
      disabled = "無効",
      api_key_set = "Gemini APIキーが設定されました",
      started_buffer = "現在のバッファでNudge Two Hatsが開始されました",
      debug_enabled = "デバッグモードが有効 - ナッジテキストが:messagesに表示されます",
      no_changes = "アドバイスを生成するための変更が検出されませんでした",
      api_key_not_set = "Gemini APIキーが設定されていません。GEMINI_API_KEY環境変数を設定するか、:NudgeTwoHatsSetApiKeyを使用して設定してください。",
      api_error = "Gemini APIエラー",
      unknown_error = "不明なエラー",
    }
  },
  
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
  
  min_interval = 30, -- Minimum interval between API calls in seconds
  
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
  
  virtual_text = {
    idle_time = 10, -- Time in minutes before showing virtual text
    cursor_idle_delay = 5, -- Time in minutes before setting timers after cursor stops
    text_color = "#000000", -- Text color in hex format
    background_color = "#FFFFFF", -- Background color in hex format
  },
}

return config
