defmodule StellarWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """

  use Phoenix.Controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, message: "Not found")
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(:unauthorized)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, message: "Unauthorized")
  end

  def call(conn, {:error, {:unprocessable_entity, message}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: StellarWeb.ChangesetJSON)
    |> render(:error, changeset: changeset)
  end

  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, message: reason)
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: StellarWeb.ErrorJSON)
    |> render(:error, message: inspect(reason))
  end
end
