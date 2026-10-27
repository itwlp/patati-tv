# TV do Patati

Página para os meninos assistirem Patati Patatá na TV sem menu, sem busca e sem aprovação no YouTube Kids:
só os vídeos da faixa escolhida, 5 por dia em rodízio, e trava ao fim.

- `index.html`: o player. Lê `playlist.json`, escolhe os vídeos do dia (janela que avança 5 posições por dia,
  todos entram no rodízio), toca em sequência e mostra "Acabou por hoje" ao fim. O limite diário fica no
  aparelho (localStorage). Modo pais: `?pai=1` na URL ou 5 toques no título em 3 s; dá botão Pular e Liberar.
- `playlist.json`: gerado pelo script. Não editar à mão.
- `config.json`: canais, faixa de duração (segundos), quantidade por dia e ids excluídos. Editar aqui.
- `atualizar-patati-tv.ps1`: lista os canais com yt-dlp (só metadados, nunca baixa vídeo), filtra, grava a
  playlist e publica (commit + push). Roda todo dia pelo Agendador do Windows e também à mão:
  `& $HOME\dev\patati-tv\atualizar-patati-tv.ps1 -Simular` mostra sem gravar.
- `logs\`: um CSV por dia (ignorado pelo git).

Publicado em GitHub Pages. Na TV: abrir a página no navegador da TV ou transmitir a aba do Chrome
(Chromecast). O primeiro toque em "Começar" é dos pais; depois os vídeos seguem sozinhos.
