# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Kniffel.Repo.insert!(%Kniffel.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Kniffel.{Server, Blockchain, Repo}
alias Kniffel.Blockchain.Crypto
alias Kniffel.Blockchain.Block
import Ecto.Query, warn: false
alias Kniffel.Request
require Logger

{:ok, private_key} = Crypto.private_key()
{:ok, public_key} = ExPublicKey.public_key_from_private_key(private_key)
{:ok, pem_string} = ExPublicKey.pem_encode(public_key)
id = ExPublicKey.RSAPublicKey.get_fingerprint(public_key)

case Server.get_server(id) do
  %Server{} = server ->
    server

  nil ->
    %Server{}
    |> Server.change_server(%{
      "url" => System.get_env("URL"),
      "public_key" => pem_string,
      "authority" => false,
      "id" => id
    })
    |> Repo.insert()
end

url = System.get_env("MASTER_URL")

from(s in Server, where: s.url == ^url, update: [set: [authority: true]])
|> Repo.update_all([])

case Server.get_server_by_url(url) do
  %Server{} = server ->
    server

  nil ->
    with {:ok, %{"server" => server}} <- Request.get(url <> "/api/servers/this"),
         %Ecto.Changeset{} = changeset <- Server.change_server(%Server{}, server),
         {:ok, server} <- Repo.insert(changeset) do
      server
    else
      {:error, %Ecto.Changeset{}} ->
        raise(
          "Master-node " <> url <> " could not be inserted into databse! Please control params."
        )

      {:error, message} ->
        Logger.debug(inspect(message))

        raise(
          "Master-node " <>
            url <> " could not be reached! Please control connection or if master-node is up."
        )
    end
end

case Blockchain.get_block(0) do
  %Block{} = block ->
    block

  nil ->
    Blockchain.genesis()
end

Logger.info("Success!")

# if System.get_env("ENV_NAME") != "production" do
#   Code.eval_file(
#     __ENV__.file
#     |> Path.dirname()
#     |> Path.join("seeds_dev.exs")
#   )
# end

# Code.eval_file(
#   __ENV__.file
#   |> Path.dirname()
#   |> Path.join("exams.exs")
# )
