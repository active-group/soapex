defmodule Soapex.Plugs.Soap do
  alias Plug.Conn
  @behaviour Plug

  require Record

  Record.defrecordp :wsdl,
    Record.extract(:"wsdl",          from_lib: "detergent/include/detergent.hrl")
  Record.defrecordp :soapEnvelope, :"soap:Envelope",
    Record.extract(:"soap:Envelope", from_lib: "detergent/include/detergent.hrl")
  Record.defrecordp :soapHeader, :"soap:Header",
    Record.extract(:"soap:Header",   from_lib: "detergent/include/detergent.hrl")
  Record.defrecordp :soapBody, :"soap:Body",
    Record.extract(:"soap:Body",     from_lib: "detergent/include/detergent.hrl")
  Record.defrecordp :soapFault, :"soap:Fault",
    Record.extract(:"soap:Fault",    from_lib: "detergent/include/detergent.hrl")

  @doc false
  def init(opts) do
    opts = Enum.into(opts, %{})
    prefix = Map.get(opts, :prefix, "p")
    :detergent.initModel(to_char_list(opts.wsdl_file), to_char_list(prefix))
    |> wsdl
    |> Enum.into(%{})
    # TODO: write a hrl, read records for later
  end

  @doc false
  def call(%Conn{} = conn, %{model: model}) do
    header = conn
      |> Conn.get_req_header("content-type")

    {:ok, body, conn} = conn |> Conn.read_body()

    case :erlsom.scan(body, model) do
      {:ok, result, _rest} ->
        soap_body = soapEnvelope(result, :Body)
        case soapBody(soap_body, :choice) do
          [soap_op] ->
            # TODO: use record macros and convert to kwlist
            %{conn | params: soap_op}
          _ ->
            client_fault(conn, model, "no such operation")
        end

      {:error, exception: {:error, message}, stack: _stack, received: _received} ->
        client_fault(conn, model, message)

      {:error, error} ->
        client_fault(conn, model, inspect(error))
    end
  end

  defp client_fault(conn, model, message) do
    fault = soapFault(
      faultcode: {:qname, 'http://schemas.xmlsoap.org/soap/envelope/', 'Client', 'soap', ''},
      faultstring: to_char_list(message))

    envelope = soapEnvelope(Header: soapHeader(),
                            Body: soapBody(choice: [fault]))

    {:ok, xml} = envelope |> :erlsom.write(model)

    conn
    |> Conn.put_resp_content_type("text/xml")
    |> Conn.send_resp(200, to_string(xml))
    |> Conn.halt
  end
end
