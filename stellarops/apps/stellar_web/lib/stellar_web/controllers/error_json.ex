defmodule StellarWeb.ErrorJSON do
  @moduledoc """
  JSON error responses.
  """

  def render("error.json", %{message: message}) do
    %{error: message}
  end

  def render("404.json", _assigns) do
    %{error: "Not Found"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal Server Error"}
  end

  # Default handler
  def render(template, _assigns) do
    %{error: Phoenix.Controller.status_message_from_template(template)}
  end
end
