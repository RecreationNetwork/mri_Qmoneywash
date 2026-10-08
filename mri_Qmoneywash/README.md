# mri_Qmoneywash — Qbox

Adaptado à base local Qbox 1.24.0, ox_inventory, ox_lib e mri_Qinteract.

Use o item `washmachine` no inventário, a pé, para instalar uma máquina à sua frente. Os itens `washmachine`, `washbattery` e `washbleach` estão registrados em `ox_inventory/data/items.lua`. Não há loja automática: distribua esses itens pela economia/administração da cidade.

Aproxime-se e abra a interação da máquina. Coloque bateria e alvejante, deposite `black_money` e retire o valor lavado na conta `cash` do Qbox. O compartimento primário devolve `black_money`. As durações originais foram mantidas: bateria de sete dias, alvejante de seis horas e processamento a cada dez segundos. Com ambos ativos, converte 6% do saldo por ciclo, com mínimo de uma unidade para não deixar resíduos presos. Tudo é configurável em `shared-side/shared.lua`.

Somente o dono pode definir a senha e recolher uma máquina vazia. Outros jogadores podem operar após autenticação por senha. Distância, instância, propriedade, quantidades e itens são verificados pelo servidor; senhas não são enviadas nas atualizações públicas.

Máquinas, saldos, insumos e senhas persistem nos KVPs do FXServer deste recurso. Preserve o armazenamento KVP e o nome do resource nos backups. Não depende de SQL adicional. Os prazos dos insumos usam horário real; o processamento ocorre enquanto o recurso está ativo. Os dados de entitydata do vRP não são importados automaticamente.

Exports exclusivamente servidor: `Wash(citizenid, item, hash, coords, bucket)` cria uma máquina para integrações confiáveis (o chamador controla o consumo do item); `UpdateObjects(oldCitizenid, newCitizenid)` transfere propriedade. Os identificadores agora são citizenids Qbox.

Dependências: `ox_lib`, `qbx_core`, `ox_inventory`, `mri_Qinteract`. Reinicie o inventário/servidor para carregar os novos itens; o `ensure [mri_beta]` já existente carrega este recurso. Teste em jogo: instalação, depósito, insumos, conversão, retirada, senha, troca de instância e persistência após reiniciar o recurso.
