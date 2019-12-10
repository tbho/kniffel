defmodule KniffelWeb.Router do
  use KniffelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :protected_browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug(KniffelWeb.Authentication, type: :api_or_browser)
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/public", KniffelWeb, as: :public do
    pipe_through(:browser)

    resources("/users", UserController, only: [:new, :create])
    resources("/sessions", SessionController, only: [:new, :create])
  end

  scope "/", KniffelWeb do
    pipe_through(:protected_browser)

    get "/", GameController, :index

    resources("/users", UserController, only: [:index, :show])

    get "/games/:id/scores", GameController, :show

    resources "/games", GameController, only: [:index, :new, :create] do
      resources "/scores", ScoreController, only: [:new]
      get "/scores/:id/re_roll", ScoreController, :re_roll
      get "/scores/:id/finish", ScoreController, :finish
      post "/scores/:id/re_roll", ScoreController, :re_roll_score
      post "/scores/:id/finish", ScoreController, :finish_score
    end

    resources "/transactions", TransactionController, only: [:new, :create]
  end

  scope "/api", KniffelWeb do
    pipe_through :api

    get "/servers/this", ServerController, :this
    post "/servers/roll", ServerController, :roll
    resources "/servers", ServerController, only: [:index, :show, :create]
    resources "/users", UserController, only: [:index, :show, :create]
    resources "/transactions", TransactionController, only: [:index, :show, :create]
    post "/blocks/:id/propose", ServerController, :propose
    post "/blocks/:id/prevote", ServerController, :prevote
    post "/blocks/:id/commit", ServerController, :commit
    resources "/blocks", BlockController, only: [:index, :show, :create]
  end
end
