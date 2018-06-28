defmodule Gringotts.Gateways.MerchantESolutions do
    @moduledoc """

  Your Application config must look something like this:

      config :gringotts, Gringotts.Gateways.MerchantESolutions,
          login: "login",
          password: "password",
          default_currency: "usd"
  """

   @test_url "https://cert.merchante-solutions.com/mes-api/tridentApi "
   @live_url "https://api.merchante-solutions.com/mes-api/tridentApi"

  use Gringotts.Gateways.Base
  use Gringotts.Adapter, required_config: [:login, :password]

  alias Gringotts.{Address, CreditCard, Money}

  @doc """
    Transfers amount from the customer to the merchant.

  Merchant E-Solutions attempts to process a purchase on behalf of the customer, by debiting
  amount from the customer's account by charging the customer's card.

  ## Example
  The following session shows how one would process a payment in one-shot,
  without (pre) authorization.

      iex> card = %CreditCard{
            first_name: "John",
            last_name: "Smith",
            number: "4242424242424242",
            year: "2017",
            month: "12",
            verification_code: "123"
          }

          address = %Address{
            street1: "123 Main",
            city: "New York",
            region: "NY",
            country: "US",
            postal_code: "11111"
          }

      iex> opts = [currency: "usd", address: address]
      iex> amount = 5

      iex> Gringotts.purchase(Gringotts.Gateways.MerchantESolutions, amount, card, opts)
  """
  @spec purchase(Money.t(), CreditCard.t() | String.t(), keyword) :: map
  def purchase(amount, card_info, options \\ %{}) do
    %{}
    |> Map.put_new(:client_reference_number, options.customer)
    |> Map.put_new(:moto_ecommerce_ind, options.moto_ecommerce_ind)
    |> add_invoice(options)
    |> add_payment_source(card_info, options)
    |> add_address(options)
    |> add_3dsecure_params(options)
    |> commit("D", amount, options)
  end

  @doc """
    Authorize Payment against Merchant-E Solutions Gateway.
  """
  def authorize(amount, card_info, options \\ %{}) do
    %{}
    |> Map.put_new(:client_reference_number, options.customer)
    |> Map.put_new(:moto_ecommerce_ind, options.moto_ecommerce_ind)
    |> add_invoice(options)
    |> add_payment_source(card_info, options)
    |> add_address(options)
    |> add_3dsecure_params(options)
    |> commit("P", amount, options)
  end

  @doc """
  Capture purchase details.
  """
  def capture(transaction_id, amount, options \\%{}) do
    %{}
    |> Map.put_new(:transaction_id, transaction_id)
    |> Map.put_new(:client_reference_number, options.customer)
    |> add_invoice(options)
    |> add_3dsecure_params(options)
    |> commit("S", amount, options)
  end

  @doc """
  Void a purchase.
  """
  def void(transaction_id, options \\ %{}) do
    %{}
    |> Map.put_new(:transaction_id, transaction_id)
    |> Map.put_new(:client_reference_number, options.customer)
    |> commit("V")
  end

  @doc false
  def refund(amount, transaction_id, options \\ %{}) do
    %{}
    |> Map.put_new(:transaction_id, transaction_id)
    |> Map.put_new(:client_reference_number, options.customer)
    |> commit("U", amount, options)
  end

  @doc false
  def store(card_info, options \\ %{}) do
    %{}
    |> Map.put_new(:client_reference_number, options.customer)
    |> add_credit_card(card_info, options)
    |> commit("T")
  end

  @doc false
  def unstore(card_id, options \\ %{}) do
    %{}
    |> Map.put_new(:client_reference_number, options.customer)
    |> Map.put_new(:card_id, card_id)
    |> commit("X")
  end

  def add_3dsecure_params(map, options) do
        map
        |> Map.put_new(:xid, options[:xid])
        |> Map.put_new(:cavv, options[:cavv])
        |> Map.put_new(:ucaf_collection_ind, options[:ucaf_collection_ind])
        |> Map.put_new(:ucaf_auth_data, options[:ucaf_auth_data])
  end

  defp add_invoice(map, options) do
    case Map.has_key?(options, :order_id) do
      true ->
        map
        |> Map.put_new(:order_id, options.order_id)
      _ -> map
    end
  end

  defp add_address(map, options) do
    address = if Map.has_key?(map, :billing_addresss), do: map.billing_address, else: map.address
    unless is_nil(address) do
        map
        |> Map.put_new(:cardholder_street_addresss, address.address1)
        |> Map.put_new(:cardhoder_zip, address.zip)
    else
        map
    end
  end

  defp add_payment_source(map, card_info, options) do
    case is_binary(card_info) do
      true ->
        map
        |> Map.put_new(:card_id, card_info)
        |> Map.put_new(:card_expiration_date, options.expiration_date)
      _ ->
        map
        |> add_credit_card(card_info, options)
    end
  end

  defp add_credit_card(map, card_info, options) do
    map
    |> Map.put_new(:card_number, card_info.card_number)
    |> Map.put_new(:cvv2, card_info.verification_value)
    |> Map.put_new(:card_exp_date, expdate(card_info))
  end

  defp production?, do: System.get_env("MIX_ENV") === "prod"

  defp expdate(card_info) do
    "#{card_info.month}#{card_info.year}"
  end

  defp commit(params, action, money \\ nil, options \\ %{}) do
    url = if production?, do: @live_url, else: @test_url

    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"},
      {"Accept", "text/html, image/gif, image/jpeg, *; q=.2, */*; q=.2"}
    ]

    unless action === "V" || is_nil(money) do
          Map.put_new(params, :trasaction_amout, money)
    end

    formatted_params = prep_data(params, action, options)

    case HTTPoison.request(:post, "#{url}", {:form, formatted_params}, headers) do
        {:ok, response} -> response_map(response)
         _ -> %{error: "There was an issue with your request"}
    end
  end

    defp response_map(%HTTPoison.Response{} = response) do
      %{
        error_code: response.body["error_code"],
        authorization: response.body["transaction_id"],
        test: !production?,
        cvv_result: response.body["cvv2_result"],
        avs_result: %{
          code: response.body["avs_result"]
        }
      }
  end

  defp prep_data(params, action, options) do
        params
        |> Map.put_new(:profile_id, options[:config][:login])
        |> Map.put_new(:profile_key, options[:config][:password])
        |> Map.put_new(:transaction_type, action)
        |> Enum.map(fn {k, v} -> Enum.join([to_string(k), to_string(v)], "=") end)
        |> Enum.join("&")
  end


end
