# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

nudge-two-hats.vim is a Neovim plugin that provides AI-powered coding advice using Gemini API. It monitors code changes and offers contextual suggestions through notifications and virtual text, implementing "nudge theory" to guide developers toward better coding practices.

## Architecture

The plugin follows a modular architecture with clear separation of concerns:

### Core Components

- **`lua/nudge-two-hats/init.lua`**: Main entry point and plugin state management
- **`lua/nudge-two-hats/config.lua`**: Configuration system with context-specific settings for notifications vs virtual text
- **`lua/nudge-two-hats/api.lua`**: Gemini API integration and text processing utilities
- **`lua/nudge-two-hats/buffer.lua`**: Buffer content tracking and diff generation
- **`lua/nudge-two-hats/timer.lua`**: Timer management for both notification and virtual text contexts
- **`lua/nudge-two-hats/virtual_text.lua`**: Virtual text display and management
- **`lua/nudge-two-hats/autocmd.lua`**: Autocommand setup and event handling
- **`lua/nudge-two-hats/prompt.lua`**: Dynamic prompt generation with persona system
- **`lua/nudge-two-hats/message_variety.lua`**: Message variety and persona selection

### Key Architectural Patterns

1. **Dual Context System**: The plugin operates in two distinct contexts:
   - **Notification context**: For prominent UI notifications with longer, actionable advice
   - **Virtual text context**: For subtle, unobtrusive hints displayed inline

2. **Buffer-Specific Timer Management**: Each buffer maintains separate timers for notifications and virtual text, preventing cross-buffer interference and reducing unnecessary API calls.

3. **Filetype-Specific Configuration**: Different prompts, personas, and behaviors can be configured per filetype within each context.

4. **State Management**: Centralized state object (`state`) tracks buffer content, timers, API call timestamps, and virtual text display status.

5. **Modular Function Wrappers**: `init.lua` provides wrapper functions that delegate to specialized modules while maintaining proper state references.

## Development Commands

### Testing
```bash
# Run all tests using Lua's busted framework
busted test/

# Run specific test file
busted test/api_spec.lua
busted test/timer_spec.lua
```

### Linting
The project uses `.luarc.json` for Lua Language Server configuration:
- Globals: `vim` is defined as a global
- Diagnostics: Hints are disabled

### Manual Testing
Use the plugin's built-in commands:
```vim
:NudgeTwoHatsStart [filetype1 filetype2 ...]  " Start monitoring (with optional filetypes)
:NudgeTwoHatsToggle [filetype1 filetype2 ...] " Toggle plugin on/off
:NudgeTwoHatsNow            " Trigger immediate advice generation
:NudgeTwoHatsDebug          " View plugin state and active timers
:NudgeTwoHatsDebugNotify    " Force notification with debug output
```

### Environment Setup
- Set `GEMINI_API_KEY` environment variable for API access
- Neovim 0.7.0+ required

## Key Implementation Details

### Timer Architecture
- **Notification timers**: Trigger API calls for prominent advice (default: 5 minutes)
- **Virtual text timers**: Handle inline text display (default: 10 minutes)
- Both timer types are buffer-specific and independently managed

### API Integration
- Uses Gemini 2.5 Flash Preview model
- Requires `GEMINI_API_KEY` environment variable
- Supports rate limiting and caching to minimize API calls
- Handles both Japanese and English content with automatic language detection

### Configuration System
The config structure separates global settings from context-specific ones:
```lua
{
  -- Global settings
  notify_interval_seconds = 300,
  virtual_text_interval_seconds = 600,
  
  -- Context-specific settings
  notification = { /* notification-specific config */ },
  virtual_text = { /* virtual text-specific config */ }
}
```

### State Management
The plugin maintains several critical state objects:
- `buf_content_by_filetype`: Tracks content changes per buffer and filetype
- `timers.notification` & `timers.virtual_text`: Active timer tracking
- `virtual_text.extmarks`: Virtual text display management
- `last_api_call_*`: API rate limiting timestamps

## Development Guidelines

### Adding New Features
1. Identify which context (notification/virtual_text) the feature affects
2. Update the relevant module in `lua/nudge-two-hats/`
3. Add corresponding tests in `test/`
4. Update configuration schema if needed

### Debugging
Enable debug mode in configuration to see detailed logging:
```lua
require("nudge-two-hats").setup({
  debug_mode = true
})
```

### Testing Strategy
The test suite uses busted with extensive mocking:
- Mock `vim.*` APIs for isolated testing
- Test UTF-8 text handling specifically
- Verify API sanitization and language detection
- Test timer and state management

This plugin demonstrates advanced Neovim plugin architecture with careful attention to performance, user experience, and maintainability.