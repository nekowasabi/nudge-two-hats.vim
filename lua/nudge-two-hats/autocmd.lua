local M = {}

-- テンポラリファイルをクリーンアップする関数
function M.clear_tempfiles(debug_mode)
  if debug_mode then
    print("[Nudge Two Hats Debug] エディタ終了時にすべてのバッファファイルをクリーンアップします")
  end
  -- /tmp配下のnudge_two_hats_buffer_*.txtファイルを削除
  local result = vim.fn.system("find /tmp -name 'nudge_two_hats_buffer_*.txt' -type f -delete")
  if debug_mode then
    print("[Nudge Two Hats Debug] バッファファイルのクリーンアップが完了しました")
  end
end

-- 自動コマンドを設定する関数
function M.setup(config)
  vim.api.nvim_create_autocmd("VimLeavePre", {
    pattern = "*",
    callback = function()
      M.clear_tempfiles(config.debug_mode)
    end
  })
end

return M
