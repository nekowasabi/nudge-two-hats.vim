local config = {
  -- Global settings that are not context-specific
  callback = "", -- Vim function name to append custom text to the prompt
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
  length_type = "characters", -- Can be "characters" or "words"
  output_language = "auto", -- Can be "auto", "en" (English), or "ja" (Japanese)
  translate_messages = true, -- Whether to translate messages to the specified language
  notify_interval_seconds = 5, -- Minimum interval between API calls in seconds
  virtual_text_interval_seconds = 10, -- Time in seconds before showing virtual text
  gemini_model = "gemini-2.5-flash-preview-05-20", -- Updated to latest Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent",
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output

  -- Context-specific settings for notifications
  notification = {
    system_prompt = "Analyze this code change and provide varied, specific advice based on the actual diff content. Consider whether the programmer is focusing on refactoring, adding new features, fixing bugs, or improving tests. Your advice should be tailored to the specific changes you see in the diff and should vary in content and style each time. (for notifications)",
    purpose = "", -- Work purpose or objective
    default_cbt = {
      role = "Notification Advisor Role", -- Differentiated
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
        callback = "",
      },
      text = {
        prompt = "Give advice about this writing, focusing on clarity and structure.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more structured writing",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Writing Coach", "Editor", "Reviewer", "Content Specialist", "Clarity Expert"},
        callback = "",
      },
      tex = {
        prompt = "Give advice about this LaTeX document, focusing on structure and formatting.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards well-formatted and structured document",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"LaTeX Expert", "Document Formatter", "Structure Specialist", "Academic Advisor", "Technical Writer"},
        callback = "",
      },
      rst = {
        prompt = "Give advice about this reStructuredText document, focusing on clarity and organization.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more organized documentation",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Documentation Expert", "Structure Advisor", "Clarity Coach", "Technical Writer", "Information Architect"},
        callback = "",
      },
      org = {
        prompt = "Give advice about this Org document, focusing on organization and structure.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards better organized and structured document",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Organization Expert", "Structure Advisor", "Productivity Coach", "Planning Specialist", "Task Manager"},
        callback = "",
      },
      lua = {
        prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing. (notification advice for Lua)", -- Differentiated
        role = "Lua Notification Advisor", -- Differentiated
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Code Reviewer", "Refactoring Expert", "Clean Code Advocate", "Performance Optimizer", "Maintainability Advisor"},
        callback = "",
      },
      python = {
        prompt = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Python Expert", "Code Reviewer", "Clean Code Advocate", "Performance Optimizer", "Pythonic Style Guide"},
        callback = "",
      },
      javascript = {
        prompt = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"JavaScript Expert", "Frontend Advisor", "Code Quality Advocate", "Performance Guru", "Best Practices Guide"},
        callback = "",
      },
    },
    notify_message_length = 10,
    virtual_text_message_length = 10,
  },

  virtual_text = {
    system_prompt = "Analyze this code change and provide varied, specific advice based on the actual diff content. Consider whether the programmer is focusing on refactoring, adding new features, fixing bugs, or improving tests. Your advice should be tailored to the specific changes you see in the diff and should vary in content and style each time. (for virtual text)",
    purpose = "",
    default_cbt = {
      role = "Virtual Text Helper Role", -- Differentiated
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
        callback = "",
      },
      text = { -- This is the specific Japanese example that needs to be preserved
        prompt = "テキスト内容を題材として、アドバイスしてください。前置きなしで、端的にメッセージのみを出力してください。",
        role = "トリックスターであり、常に民衆の意表を突く発言のみを行う",
        direction = "意味深なアドバイスを行う",
        emotion = "Empathetic and understanding",
        tone = "前置きなしで、直接的に",
        hats = { "law", "chaos", "neutral", "trickster" },
        purpose = "集中が途切れないように、ナッジによってさりげなく現在の行動を促す",
        callback = "NudgeCallback",
      },
      tex = {
        prompt = "Give advice about this LaTeX document, focusing on structure and formatting.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards well-formatted and structured document",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"LaTeX Expert", "Document Formatter", "Structure Specialist", "Academic Advisor", "Technical Writer"},
        callback = "",
      },
      rst = {
        prompt = "Give advice about this reStructuredText document, focusing on clarity and organization.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more organized documentation",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Documentation Expert", "Structure Advisor", "Clarity Coach", "Technical Writer", "Information Architect"},
        callback = "",
      },
      org = {
        prompt = "Give advice about this Org document, focusing on organization and structure.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards better organized and structured document",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Organization Expert", "Structure Advisor", "Productivity Coach", "Planning Specialist", "Task Manager"},
        callback = "",
      },
      lua = {
        prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing. (virtual text advice for Lua)", -- Differentiated
        role = "Lua Virtual Text Helper", -- Differentiated
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Code Reviewer", "Refactoring Expert", "Clean Code Advocate", "Performance Optimizer", "Maintainability Advisor"},
        callback = "",
      },
      python = {
        prompt = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"Python Expert", "Code Reviewer", "Clean Code Advocate", "Performance Optimizer", "Pythonic Style Guide"},
        callback = "",
      },
      javascript = {
        prompt = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
        role = "Cognitive behavioral therapy specialist",
        direction = "Guide towards clearer and more maintainable code",
        emotion = "Empathetic and understanding",
        tone = "Supportive and encouraging but direct",
        hats = {"JavaScript Expert", "Frontend Advisor", "Code Quality Advocate", "Performance Guru", "Best Practices Guide"},
        callback = "",
      },
    },
    notify_message_length = 10,
    virtual_text_message_length = 10,
    text_color = "#000000",
    background_color = "#FFFFFF",
  },
}
return config
