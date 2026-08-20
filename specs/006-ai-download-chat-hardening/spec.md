# AI download and chat hardening

Status: implemented; automated gate green  
Tier: T1

## Objetivo

Manter downloads de modelos ativos quando o app entra em background, impedir que o launch overlay reapareça durante o uso e transformar o surface de IA em um chat normal, sem bloquear a conversa com uma tela de catálogo.

## Requisitos

- Usar uma sessão `URLSessionConfiguration.background` identificada e restaurável pelo sistema.
- Persistir o modelo/tarefa ativa, restaurar o progresso quando o app for reaberto e validar tamanho/checksum antes da instalação.
- O launch screen aparece somente durante o lançamento inicial e a primeira leitura do vault; reloads posteriores não cobrem o app.
- O chat mostra mensagens em sequência, composer inferior, envio/parar e configuração de modelo no topo.
- Escolher um modelo instalado o seleciona; escolher um não instalado inicia o download.
- O download aparece como estado local de configuração/composer, nunca como launch screen.

## Fora do escopo

- Download automático sem escolha do usuário.
- Inferência em background.
- Notificação push própria ou catálogo remoto.
- Mais de uma transferência simultânea nesta fatia.

## Aceitação

- Dado um download em andamento, quando o app é suspenso e retomado, a tarefa continua/restaura em vez de reiniciar silenciosamente.
- Dado um reload do vault, o conteúdo atual permanece visível sem piscar o Flint Launch Screen.
- Dado o chat aberto, a pessoa consegue escolher/configurar o modelo no topo, digitar no campo inferior e enviar uma pergunta.
- Dado um modelo não instalado, selecionar o modelo inicia o download e mantém o chat utilizável como estado de espera.
- Dado um arquivo parcial, tamanho incorreto ou checksum incorreto, ele não vira modelo instalado.

### Onde isto pode dar errado

- O iOS controla quando uma sessão em background recebe tempo; “continuar em segundo plano” significa transferência gerenciada pelo sistema, não execução livre da interface.
- O primeiro download pode exceder memória/armazenamento disponíveis; o modelo continua sujeito aos limites físicos do aparelho.
- A validação e instalação acontecem depois do callback de download; a UI precisa continuar mostrando “validando” numa evolução futura se essa etapa ficar perceptível.
