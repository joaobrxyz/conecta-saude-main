# Conecta Saúde

Portal Angular integrado aos serviços de identidade, agendamento e prontuário por um único API Gateway.

## Executar localmente

Requisitos: Java 21 ou superior, Maven 3.9+, Node.js compatível com Angular 20 (20.19+ ou 22.12+), npm e Docker.

1. Inicie os bancos, na raiz do projeto:

   ```powershell
   docker compose -f identity-service/docker-compose.yml up -d
   docker compose -f appointment-service/docker-compose.yml up -d
   docker compose -f clinical-service/docker-compose.yml up -d
   ```

2. Execute cada comando em um terminal separado:

   ```powershell
   mvn -f identity-service/pom.xml spring-boot:run
   mvn -f appointment-service/pom.xml spring-boot:run
   mvn -f clinical-service/pom.xml spring-boot:run
   mvn -f api-gateway/pom.xml spring-boot:run
   ```

3. Inicie o portal:

   ```powershell
   cd frontend
   npm ci
   npm start
   ```

Abra http://localhost:4200. O Angular envia `/api/*` ao gateway em `8080`, removendo `/api` por meio do [proxy de desenvolvimento](frontend/proxy.conf.json). O navegador não precisa conhecer os endereços dos microsserviços.

| Serviço | Porta | Banco |
| --- | --- | --- |
| Gateway | 8080 | — |
| Agendamento | 8081 | PostgreSQL 5433 |
| Identidade | 8082 | PostgreSQL 5434 |
| Clínico | 8083 | MongoDB 27017 |

O serviço clínico respeita a variável `MONGODB_URI`, se definida no terminal. Para usar explicitamente o MongoDB local, execute `$env:MONGODB_URI = 'mongodb://root:rootpassword@localhost:27017/clinical_db?authSource=admin&uuidRepresentation=standard'` no terminal desse serviço antes de iniciá-lo.

### Primeiro administrador

Para uma base local sem administrador ativo, inicie **apenas o serviço de identidade** com o perfil `local` e credenciais escolhidas por você:

```powershell
$env:APP_BOOTSTRAP_ADMIN_EMAIL = 'seu-email@example.com'
$env:APP_BOOTSTRAP_ADMIN_PASSWORD = 'substitua-por-uma-senha-forte'
mvn -f identity-service/pom.xml spring-boot:run '-Dspring-boot.run.profiles=local'
```

O bootstrap exige senha com pelo menos 12 caracteres e não altera um administrador existente. Remova essas variáveis após a primeira inicialização. Nas próximas execuções, utilize o perfil padrão. A criação pública de contas registra somente pacientes; médicos, recepcionistas e administradores são cadastrados pela área administrativa.

## Fluxos integrados

| Área | Operações |
| --- | --- |
| Acesso | Login por e-mail, cadastro de paciente, perfil identificado pelo JWT, sessão temporária ou persistente, renovação de token e logout |
| Paciente | Painel, agendamento, listagem e cancelamento de consultas, histórico clínico, sinais vitais, prescrições, download dos próprios exames e edição do próprio perfil |
| Recepção | Agenda, cadastro/edição/inativação de pacientes, agendamento, check-in, registro de falta e cancelamento |
| Médico | Agenda, fila, início e conclusão de atendimento, prontuário, prescrições, sinais vitais, adendos privados e publicação de exames |
| Administração | Indicadores calculados dos dados reais, usuários, especialidades e agenda |
| Todas as contas | Edição do próprio nome/e-mail/telefone e troca de senha mediante senha atual |

O fluxo de atendimento é `AGENDADA → EM_ESPERA → EM_ATENDIMENTO → REALIZADA`. O médico também pode iniciar diretamente uma consulta agendada. Cancelamento e registro de falta respeitam as regras do serviço de agendamento. O formulário permite salvar o prontuário e concluir a consulta separadamente; um atendimento pode ser reaberto após recarregar a página sem cadastrar novamente o prontuário.

Consultas são agendadas de segunda a sábado, entre 08h e 17h30, com antecedência mínima de 30 minutos. Datas e horas de consultas seguem o horário local da clínica; mantenha os serviços na mesma zona de tempo (America/Sao_Paulo).

As telas usam componentes compartilhados em [shared](frontend/src/app/shared), preservando a navegação por perfil e a identidade visual do portal. Os contratos HTTP, interceptador de autenticação e guards ficam em [core](frontend/src/app/core). As listas de seleção e os indicadores carregam todas as páginas retornadas pelo cadastro; a listagem de usuários oferece busca e paginação visual.

### Funcionalidades ainda indisponíveis

Os serviços existentes não implementam notificações, salas de atendimento, auditoria e configurações gerais da clínica. O portal informa a indisponibilidade e não apresenta exemplos como se fossem dados reais.

Renovação de receita e exportação PDF eram simulações no back end; esses endpoints agora retornam `501` e não são oferecidos como ações funcionais. O pedido e a redefinição de senha estão ligados à API, mas o envio de e-mail ainda não existe: em desenvolvimento, o serviço de identidade registra o link no console. O link aponta para `/redefinir-senha?token=...` no portal; configure `APP_FRONTEND_URL` para outro endereço. O portal informa essa limitação ao solicitar recuperação.

## Validação

```powershell
npm --prefix frontend run build
npm --prefix frontend test -- --watch=false --browsers=ChromeHeadless
mvn -f identity-service/pom.xml verify
mvn -f appointment-service/pom.xml verify
mvn -f clinical-service/pom.xml verify
mvn -f api-gateway/pom.xml verify
```

Os testes de contexto dos microsserviços utilizam os bancos locais; inicie os containers antes de executá-los. Os testes do Angular usam HTTP simulado e não acessam cadastros reais.

Após gerar os quatro pacotes com `mvn verify`, execute o teste ponta a ponta:

```powershell
node scripts/verify-integration.mjs
```

O [teste de integração](scripts/verify-integration.mjs) cria bancos temporários nos containers locais, inicia os serviços nas portas 18080–18083 e o Angular na 14200, e testa HTTP através do proxy Angular e do gateway. Ele cobre os quatro perfis, cadastro, agendamento, check-in, prontuário, prescrições, privacidade, senha e renovação/logout. Ao terminar, encerra os processos iniciados e remove apenas os bancos temporários criados pelo teste. Os logs ficam em `.integration-*.runtime.log` para diagnóstico. Os containers e bancos de desenvolvimento existentes são preservados.

Validação concluída em 07/10/2026: build de produção do Angular, 36 testes do front end, suítes dos quatro serviços e 56 verificações HTTP de integração aprovadas. O teste HTTP verifica os contratos e a persistência através do proxy; não substitui uma revisão visual das telas no navegador.

## Publicação

O build fica em `frontend/dist/portal-conecta/browser`. Configure o servidor web para servir o Angular com fallback para `index.html` e encaminhar `/api/*` ao gateway, removendo `/api`. O proxy de `ng serve` não é incluído no build de produção. Exponha somente o gateway e use HTTPS; configure o mesmo `API_SECURITY_TOKEN_SECRET` nos três serviços e substitua as credenciais locais dos bancos antes de publicar.

Cada microsserviço e o front end são submódulos Git. As alterações devem ser versionadas dentro de cada submódulo; depois, atualize as referências no repositório principal.
