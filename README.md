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
- Context-specific configurations for notifications and virtual text.

test

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

The plugin offers a range of configuration options. Notably, settings related to prompt generation, message length, and appearance are now separated into `notification` and `virtual_text` sections. This allows for distinct behaviors and appearances for UI notifications versus the more subtle virtual text hints.

Here's an example of the configuration structure:

```lua
require("nudge-two-hats").setup({
  -- === Global Settings ===
  -- These settings apply to both notification and virtual text contexts unless overridden within a specific context.
  
  callback = "", -- Global Vim function name to append its return value to the prompt if context-specific callback is not set.
  
  translations = { -- For UI messages from the plugin itself
    en = {
      enabled = "enabled",
      disabled = "disabled",
      -- ... other plugin messages
    },
    ja = {
      enabled = "有効",
      disabled = "無効",
      -- ... other plugin messages
    }
  },
  
  length_type = "characters", -- Default length unit: "characters" (good for CJK) or "words" (good for English)
  output_language = "auto",   -- AI response language: "auto", "en", "ja"
  translate_messages = true,  -- Whether to translate AI messages to output_language
  
  notify_interval_seconds = 300,     -- Default: 5 minutes (300 seconds) for notifications
  virtual_text_interval_seconds = 600, -- Default: 10 minutes (600 seconds) for virtual text
  
  gemini_model = "gemini-2.5-flash-preview-05-20", -- Specify the Gemini model
  api_endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-preview-05-20:generateContent",
  
  debug_mode = false, -- Set to true to print debug information to Vim's :messages output
  
  -- === Notification Context Settings ===
  notification = {
    system_prompt = "As a notification, analyze this code change and provide concise, actionable advice. Consider if the user is refactoring, adding features, fixing bugs, or improving tests. Focus on being a helpful, brief coding companion.",
    purpose = "General coding assistance for notifications", -- Context-specific work purpose
    
    default_cbt = { -- Default CBT persona for notifications
      role = "Notification Advisor",
      direction = "Guide towards focused and effective coding practices via notifications.",
      emotion = "Calm and direct",
      tone = "Brief and encouraging",
      hats = {"Coding Mentor", "Quick Advisor"},
    },
    
    filetype_prompts = { -- Filetype-specific overrides for notifications
      lua = {
        prompt = "For this Lua code, provide a brief notification-style tip.",
        role = "Lua Notification Specialist",
        hats = {"Lua Quick Tip Generator"},
      },
      python = {
        prompt = "Python notification: offer a concise suggestion.",
        role = "Python Notify Helper",
      },
      -- Add other filetypes as needed
    },
    
    notify_message_length = 150,       -- Max message length for notifications (using 'length_type' unit)
    virtual_text_message_length = 10,  -- Fallback if used in VT context, less relevant here
  },
  
  -- === Virtual Text Context Settings ===
  virtual_text = {
    system_prompt = "As unobtrusive virtual text, analyze this code change. Offer subtle, thought-provoking insights or questions related to the user's likely intent (refactoring, feature work, bug fixing, testing). Aim to be a gentle, almost subliminal guide.",
    purpose = "Subtle guidance for virtual text", -- Context-specific work purpose
    
    default_cbt = { -- Default CBT persona for virtual text
      role = "Virtual Text Companion",
      direction = "Gently steer towards better code structure and problem-solving via virtual text.",
      emotion = "Subtle and inquisitive",
      tone = "Minimalist and thought-provoking",
      hats = {"Code Whisperer", "Reflective Partner"},
    },
    
    filetype_prompts = { -- Filetype-specific overrides for virtual text
      lua = {
        prompt = "For this Lua segment, provide a very short virtual text hint.",
        role = "Lua Virtual Text Assistant",
        hats = {"Lua Micro-Hint Provider"},
      },
      python = {
        prompt = "Python virtual text: offer a compact insight.",
        role = "Python VT Guide",
      },
      text = { -- Example of a highly customized prompt for 'text' filetype in virtual text
        prompt = "このテキスト断片について、非常に短い、示唆に富むコメントを一行で。",
        role = "俳句ボット",
        direction = "簡潔な一行コメントを生成する",
        emotion = "穏やか",
        tone = "詩的かつ簡潔に",
        hats = {"禅師", "詩人"},
        purpose = "執筆中の思考を中断させずに、新たな視点を提供する",
        callback = "", -- No callback for this specific one, but could be defined
      },
      -- Add other filetypes as needed
    },
    
    notify_message_length = 10,        -- Fallback if used in Notification context, less relevant here
    virtual_text_message_length = 80, -- Max message length for virtual text (using 'length_type' unit)
    
    -- Appearance settings specific to virtual text
    text_color = "#AABBCC",       -- Text color in hex format (e.g., light grey)
    background_color = "#112233", -- Background color in hex format (e.g., dark blue)
  }
})
```

## Usage

1. Set your Gemini API key:
   - Set the GEMINI_API_KEY environment variable in your shell environment
   - Example: `export GEMINI_API_KEY="your_api_key_here"`

2. Configure the purpose parameter (optional, can also be set per context - see above):
   ```lua
   -- This top-level purpose would be a fallback if not set in notification/virtual_text contexts
   require("nudge-two-hats").setup({
     notification = {
       purpose = "code review for notifications", 
     },
     virtual_text = {
       purpose = "refactoring assistance for virtual text",
     }
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

After a period of cursor inactivity (defined by `virtual_text_interval_seconds`), the plugin will display AI-generated advice as virtual text at the end of the current line. This provides contextual suggestions without disrupting your workflow. Its appearance and content can be configured separately in the `virtual_text` section of the setup.

### Notification Display
Notifications provide more direct advice and can be configured independently in the `notification` section of the setup.

### Filetype-Specific Tracking

The plugin tracks changes by filetype, allowing for more accurate and relevant suggestions based on the type of file you're editing. You can specify multiple filetypes to monitor for a single buffer. Prompts and CBT personas can be customized per filetype within both `notification` and `virtual_text` contexts.

### Purpose Parameter

The purpose parameter enhances AI suggestions by providing context about your current work objective. This can be set globally or, more effectively, within each `notification` and `virtual_text` context to tailor AI responses.

### Callback

You can specify a Vim function name via the `callback` option (globally or within a filetype prompt definition in either context). When defined, the plugin calls this function and appends its return value to the prompt. If the function does not exist, an empty string is appended.

## Requirements

- Neovim 0.7.0+
- Gemini API key
