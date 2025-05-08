# nudge-two-hats.vim
<img src="https://github.com/user-attachments/assets/8f22c6fb-18cf-4c71-ae80-489829ebd9c6" width="30%">

A plugin that nudges you with AI about which hat you are wearing and what you should do in the situation. Based on [Nudge theory](https://en.wikipedia.org/wiki/Nudge_theory).

Inspired by [An example of preparatory refactoring](https://martinfowler.com/articles/preparatory-refactoring-example.html)

## Features

- Monitors your code changes in real-time
- Uses Gemini AI to analyze which "hat" you're wearing (refactoring or feature development)
- Provides concise advice via notifications
- Toggle functionality on/off as needed

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
  system_prompt = "Give advice about this code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
  
  -- File type specific prompts with enhanced structure
  filetype_prompts = {
    -- Text/writing related filetypes
    markdown = {
      prompt = "Give advice about this writing, focusing on clarity and structure.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more structured writing",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
    -- Other filetypes configured similarly
    
    -- Programming languages (examples)
    lua = {
      prompt = "Give advice about this Lua code change, focusing on which hat (refactoring or feature) the programmer is wearing.",
      role = "Cognitive behavioral therapy specialist",
      direction = "Guide towards clearer and more maintainable code",
      emotion = "Empathetic and understanding",
      tone = "Supportive and encouraging but direct",
    },
  },
  
  -- Message length configuration
  message_length = 10, -- Default length of the advice message
  length_type = "characters", -- Can be "characters" (for Japanese) or "words" (for English)
  
  -- Timing configuration
  execution_delay = 60000, -- Delay in milliseconds (1 minute)
  min_interval = 1, -- Minimum interval between API calls in minutes
  
  -- API configuration
  gemini_model = "gemini-2.5-flash-preview-04-17", -- Model to use
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-04-17:generateContent",
  
  -- Debug configuration
  debug_mode = false, -- When true, prints nudge text to Vim's :messages output
})
```

## Usage

1. Set your Gemini API key:
   - Set the GEMINI_API_KEY environment variable in your shell environment
   - Example: `export GEMINI_API_KEY="your_api_key_here"`

2. Start monitoring the current buffer:
```
:NudgeTwoHatsStart
```

3. Toggle the plugin on/off:
```
:NudgeTwoHatsToggle
```

4. Execute a nudge immediately (without waiting for the interval):
```
:NudgeTwoHatsNow
```

5. Toggle debug mode (prints nudge text to Vim's `:messages`):
```
:NudgeTwoHatsDebugToggle
```

## Requirements

- Neovim 0.7.0+
- Gemini API key
