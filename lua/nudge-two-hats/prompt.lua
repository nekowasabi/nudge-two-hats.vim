-- prompt.lua
-- プロンプト生成のための機能

local M = {}

-- プロンプトを生成する関数
-- @param role - ロール（役割）
-- @param selected_hat - 選択された帽子
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
function M.generate_prompt(role, selected_hat, direction, emotion, tone, prompt_text)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s wearing the %s hat.
%s.
With %s emotions and a %s tone, I will advise:
%s]]

    -- フォーマットを適用
    return string.format(base, role, selected_hat, direction, emotion, tone, prompt_text)
end

-- 帽子がない場合のプロンプトを生成する関数
-- @param role - ロール（役割）
-- @param direction - 方向性や指示
-- @param emotion - 感情
-- @param tone - トーン（口調）
-- @param prompt_text - プロンプトのテキスト内容
function M.generate_prompt_without_hat(role, direction, emotion, tone, prompt_text)
    -- ヒアドキュメント構文を使用して、複数行のプロンプトを作成
    local base = [[
I am a %s.
%s.
With %s emotions and a %s tone, I will advise:
%s]]

    -- フォーマットを適用
    return string.format(base, role, direction, emotion, tone, prompt_text)
end

return M
