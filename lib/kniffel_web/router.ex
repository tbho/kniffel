defmodule KniffelWeb.Router do
  use KniffelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", KniffelWeb do
    pipe_through :browser

    get "/", PageController, :index

    resources "/users", UserController, only: [:index, :show, :new, :create]

    resources "/games", GameController, only: [:index, :show, :new, :create] do
      resources "/scores", ScoreController, only: [:show, :new, :edit,:update]
      post "/scores/:id/re_roll", ScoreController, :re_roll
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", KniffelWeb do
  #   pipe_through :api
  # end
end
