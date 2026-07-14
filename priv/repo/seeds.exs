# Idempotent seeds. Run with: mix run priv/repo/seeds.exs
alias PhoenixChat.{Accounts, Chat, Repo}
alias PhoenixChat.Accounts.User

_workspace = Chat.default_workspace!()
general = Chat.ensure_general_channel!()

if Mix.env() == :dev do
  demo = [
    {"ana@demo.local", "ana"},
    {"marko@demo.local", "marko"},
    {"jovana@demo.local", "jovana"}
  ]

  users =
    for {email, username} <- demo do
      case Accounts.get_user_by_email(email) do
        nil ->
          user =
            Repo.insert!(%User{
              email: email,
              username: username,
              hashed_password: Bcrypt.hash_pwd_salt("lozinka12345"),
              confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
            })

          {:ok, _} = Chat.join_general(user)
          user

        %User{} = user ->
          user
      end
    end

  [ana, marko, jovana] = users

  {existing, _cursor} = Chat.list_messages(general, limit: 1)

  if existing == [] do
    {:ok, _} = Chat.send_message(ana, general, %{body: "Dobrodošli u PhoenixChat! 🎉"})
    {:ok, _} = Chat.send_message(marko, general, %{body: "Radi ovo odlično."})
    {:ok, _} = Chat.send_message(jovana, general, %{body: "Pozdrav ekipa!"})

    dm = Chat.get_or_create_dm!(ana, marko)
    {:ok, _} = Chat.send_message(ana, dm, %{body: "Marko, vidimo se na huddle-u?"})
  end
end
