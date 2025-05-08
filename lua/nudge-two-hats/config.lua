local config = {
  system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  
  default_cbt = {
    role = "認知行動療法の専門家", -- Cognitive behavioral therapy specialist
    direction = "健全な思考パターンと行動への導き", -- Guide towards healthier thought patterns and behaviors
    emotion = "共感的で理解のある", -- Empathetic and understanding
    tone = "支持的で励ましながらも直接的な", -- Supportive and encouraging but direct
  },
  
  filetype_prompts = {
    markdown = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "認知行動療法の専門家",
      direction = "明確で体系的な文章への導き", 
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    text = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "認知行動療法の専門家",
      direction = "明確で体系的な文章への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    tex = {
      prompt = "Give advice about this LaTeX document, focusing on structure and formatting.",
      role = "認知行動療法の専門家",
      direction = "整然としたフォーマットと構造への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    rst = {
      prompt = "Give advice about this reStructuredText document, focusing on clarity and organization.",
      role = "認知行動療法の専門家",
      direction = "明確で整理された文書への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    org = {
      prompt = "Give advice about this Org document, focusing on organization and structure.",
      role = "認知行動療法の専門家",
      direction = "整理された構造的な文書への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    
    lua = {
      prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "認知行動療法の専門家",
      direction = "コードの明確性と保守性の向上への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    python = {
      prompt = "Give advice about this Python code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "認知行動療法の専門家",
      direction = "コードの明確性と保守性の向上への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
    },
    javascript = {
      prompt = "Give advice about this JavaScript code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "認知行動療法の専門家",
      direction = "コードの明確性と保守性の向上への導き",
      emotion = "共感的で理解のある",
      tone = "支持的で励ましながらも直接的な",
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
