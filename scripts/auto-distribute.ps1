# auto-distribute.ps1
# 新規ウィンドウが開いたとき、最もウィンドウ数が少ないワークスペースへ自動移動する
#
# 仕組み:
#   komorebi は「Named Pipe」という仕組みでイベント（ウィンドウが開いた、閉じた等）を
#   外部スクリプトに通知できる。このスクリプトはその通知を受け取り、
#   新しいウィンドウ（Manage イベント）が来たら、一番空いているワークスペースへ移動させる。

# komorebic state の出力は UTF-8 だが、PowerShell はデフォルトで別のエンコーディングを使う。
# これを明示的に UTF-8 に揃えないと、日本語ウィンドウタイトル等を含む JSON のパースに失敗する。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# パイプの名前（komorebi とこのスクリプトの間の通信チャンネルの名前）
$PIPE_NAME = "komorebi-auto-distribute"

# 既に同じ名前で購読していたら解除してから、改めてイベント購読を登録する
komorebic unsubscribe-pipe $PIPE_NAME 2>&1 | Out-Null
komorebic subscribe-pipe $PIPE_NAME

# 無限ループ: パイプが切れても再接続してイベントを受け取り続ける
while ($true) {
    try {
        # Named Pipe をサーバーとして作成する
        # komorebi が「クライアント」としてこのパイプに接続し、イベントを書き込んでくる
        # こちらは「サーバー」としてパイプを作り、komorebi からの接続を待つ
        $pipe = [System.IO.Pipes.NamedPipeServerStream]::new($PIPE_NAME, [System.IO.Pipes.PipeDirection]::In)
        # komorebi が接続してくるまで待機（ブロッキング）
        $pipe.WaitForConnection()
        # パイプから文字列を1行ずつ読むためのリーダー
        $reader = [System.IO.StreamReader]::new($pipe)

        # パイプからイベントが来るたびに1行ずつ読み取る
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not $line) { continue }

            # 各行は JSON 形式のイベントデータ。パースして PowerShell オブジェクトに変換
            try {
                $event = $line | ConvertFrom-Json
            } catch {
                continue
            }

            # 「Manage」イベント = 新しいウィンドウが komorebi の管理下に入った瞬間
            # それ以外のイベント（フォーカス変更など）は無視する
            if ($event.event.type -ne "Manage") { continue }

            # komorebi の現在の状態（どのモニターにどのワークスペースがあり、
            # 各ワークスペースに何個のウィンドウがあるか）を JSON で取得
            try {
                # komorebic state は複数行で JSON を出力するので、-join で1つの文字列に結合する
                $stateJson = (komorebic state 2>$null) -join "`n"
                $state = $stateJson | ConvertFrom-Json
            } catch {
                continue
            }

            # 現在フォーカスされているモニターの情報を取り出す
            $monitor = $state.monitors.elements[$state.monitors.focused]
            # そのモニターにある全ワークスペースのリスト
            $workspaces = $monitor.workspaces.elements
            # 現在アクティブなワークスペースの番号（0始まり）
            $focusedIdx = $monitor.workspaces.focused

            # 全ワークスペースを調べて、最もウィンドウ数（コンテナ数）が少ないものを探す
            $currentCount = 0              # 現在のワークスペースのウィンドウ数
            $minCount = [int]::MaxValue    # 最小ウィンドウ数（最初は「無限大」にしておく）
            $minIdx = $focusedIdx          # 最小ウィンドウ数のワークスペース番号

            for ($i = 0; $i -lt $workspaces.Count; $i++) {
                $ws = $workspaces[$i]
                # そのワークスペースにあるウィンドウ（コンテナ）の数を数える
                $count = 0
                if ($ws.containers -and $ws.containers.elements) {
                    $count = $ws.containers.elements.Count
                }

                # 現在のワークスペースのウィンドウ数を記録
                if ($i -eq $focusedIdx) {
                    $currentCount = $count
                }

                # これまでで一番少なければ更新
                if ($count -lt $minCount) {
                    $minCount = $count
                    $minIdx = $i
                }
            }

            # 移動条件:
            #   1. 現在のワークスペースにウィンドウが2個以上ある（1個なら移動不要）
            #   2. より空いているワークスペースが別にある
            # move-to-workspace はウィンドウだけ移動し、フォーカスは今のワークスペースに残る
            if ($currentCount -ge 2 -and $minIdx -ne $focusedIdx) {
                komorebic move-to-workspace $minIdx
            }
        }

        $reader.Close()
        $pipe.Close()
    } catch {
        # パイプ接続に失敗した場合（komorebi がまだ起動していない等）、
        # 少し待ってから再接続を試みる
        Start-Sleep -Seconds 2
    }
}
