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

    get "/", GameController, :index

    resources "/users", UserController, only: [:index, :show, :new, :create]

    get "games/:id/scores", GameController, :show

    resources "/games", GameController, only: [:index, :new, :create] do
      resources "/scores", ScoreController, only: [:new]
      get "/scores/:id/re_roll", ScoreController, :re_roll
      get "/scores/:id/finish", ScoreController, :finish
      post "/scores/:id/re_roll", ScoreController, :re_roll_score
      post "/scores/:id/finish", ScoreController, :finish_score
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", KniffelWeb do
  #   pipe_through :api
  # end
end
