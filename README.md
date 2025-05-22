# nudge-two-hats.vim
<img src="https://github.com/user-attachments/assets/8f22c6fb-18cf-4c71-ae80-489829ebd9c6" width="30%">

A plugin that nudges you with AI about which hat you are wearing and what you should do in the situation. Based on [Nudge theory](https://en.wikipedia.org/wiki/Nudge_theory).

Inspired by [An example of preparatory refactoring](https://martinfowler.com/articles/preparatory-refactoring-example.html)

## Features

- Monitors your code changes in real-time
- Uses Gemini AI to analyze which "hat" you're wearing (refactoring or feature development)
- Provides short advice via notifications and virtual text
- Buffer-specific timer management to reduce API calls
- Filetype-specific prompts and tracking
- Toggle functionality on/off as needed
- Purpose parameter to enhance AI suggestions

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "nekowasabi/nudge-two-hats.vim",
  config = function()
    require("nudge-two-hats").setup({
      -- Optional configuration
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "nekowasabi/nudge-two-hats.vim",
  config = function()
    require("nudge-two-hats").setup()
  end
}
```

## Configuration

```lua
require("nudge-two-hats").setup({
  -- Prompt configuration
  system_prompt = "Analyze this code change and provide varied, specific advice based on the actual diff content. Consider whether the programmer is focusing on refactoring, adding new features, fixing bugs, or improving tests.",
  purpose = "", -- Work purpose or objective (e.g., "code review", "refactoring", "feature development")
  callback = "", -- Vim function name to append its return value to the prompt
  
  -- Default CBT (Cognitive Behavioral Therapy) settings
  default_cbt = {
    role = "Cognitive behavioral therapy specialist",
    direction = "Guide towards healthier thought patterns and behaviors",
    emotion = "Empathetic and understanding",
    tone = "Supportive and encouraging but direct",
    hats = {"Therapist", "Coach", "Mentor", "Advisor", "Counselor"},
  },
  
  -- File type specific prompts with enhanced structure
  filetype_prompts = {
    -- Text/writing related filetypes
    markdown = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Writing Coach", "Editor", "Reviewer", "Content Specialist", "Clarity Expert"},
      callback = "", -- Optional Vim function for markdown files
    },
    -- Other filetypes configured similarly
    
    -- Programming languages (examples)
    lua = {
      prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
      hats = {"Code Reviewer", "Refactoring Expert", "Clean Code Advocate", "Performance Optimizer", "Maintainability Advisor"},
    },
  },
  
  -- Message length configuration
  message_length = 10, -- Default length of the advice message
  length_type = "characters", -- Can be "characters" (for Japanese) or "words" (for English)
  
  -- Language configuration
  output_language = "auto", -- Can be "auto", "en" (English), or "ja" (Japanese)
  translate_messages = true, -- Whether to translate messages to the specified language
  
  -- Timing configuration
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  notify_min_interval = 1, -- Minimum interval between notification API calls in minutes
  virtual_text_min_interval = 1, -- Minimum interval between virtual text API calls in minutes
  
  -- API configuration
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Model to use
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  
  -- Debug configuration
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
  
  -- Virtual text configuration
  virtual_text = {
    idle_time = 10, -- Time in minutes before showing virtual text
    text_color = "#000000", -- Text color in hex format
    background_color = "#FFFFFF", -- Background color in hex format
  },
})
```

## Usage

1. Set your Gemini API key:
   - Set the GEMINI_API_KEY environment variable in your shell environment
   - Example: `export GEMINI_API_KEY="your_api_key_here"`

2. Configure the purpose parameter (optional):
   ```lua
   require("nudge-two-hats").setup({
     -- Set the purpose for your current work
     purpose = "code review", -- or "refactoring", "feature development", etc.
     -- Other configuration options...
   })
   ```

3. Start monitoring the current buffer:
   ```
   :NudgeTwoHatsStart [filetype1 filetype2 ...]
   ```
   Optionally specify filetypes to monitor (defaults to current buffer's filetype)

4. Toggle the plugin on/off:
   ```
   :NudgeTwoHatsToggle [filetype1 filetype2 ...]
   ```
   Optionally specify filetypes to monitor (defaults to current buffer's filetype)

5. Execute a nudge immediately (without waiting for the interval):
   ```
   :NudgeTwoHatsNow
   ```

6. Toggle debug mode (prints nudge text to Vim's `:messages`):
   ```
   :NudgeTwoHatsDebugToggle
   ```

7. Debug virtual text display:
   ```
   :NudgeTwoHatsDebugVirtualText
   ```

8. Debug virtual text timer:
   ```
   :NudgeTwoHatsDebugVirtualTextTimer
   ```

## How It Works

### Buffer-Specific Timer Management

The plugin uses buffer-specific timers to reduce API calls and improve performance. Timers are only active for the current buffer and are automatically stopped when switching between buffers. This prevents unnecessary API calls from inactive buffers.

### Virtual Text Display

After a period of cursor inactivity (defined by `virtual_text.idle_time`), the plugin will display AI-generated advice as virtual text at the end of the current line. This provides contextual suggestions without disrupting your workflow.

### Filetype-Specific Tracking

The plugin tracks changes by filetype, allowing for more accurate and relevant suggestions based on the type of file you're editing. You can specify multiple filetypes to monitor for a single buffer.

### Purpose Parameter

The purpose parameter enhances AI suggestions by providing context about your current work objective. This helps the AI generate more relevant and helpful advice tailored to your specific task.

### Callback

You can specify a Vim function name via the `callback` option. When defined, the plugin calls this function and appends its return value to the prompt. If the function does not exist, an empty string is appended.

## Requirements

- Neovim 0.7.0+
- Gemini API key
