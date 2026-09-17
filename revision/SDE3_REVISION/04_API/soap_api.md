# SOAP API - Revision

## What is SOAP?
- Simple Object Access Protocol
- Protocol (strict standard) vs REST style
- XML only
- Transport: HTTP, SMTP, TCP
- W3C standard

## Structure
```xml
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope/">
  <soap:Header>
    <auth>token</auth>
  </soap:Header>
  <soap:Body>
    <m:GetUser>
      <m:UserId>123</m:UserId>
    </m:GetUser>
  </soap:Body>
  <soap:Fault>
    <faultcode>soap:Server</faultcode>
    <faultstring>Error</faultstring>
  </soap:Fault>
</soap:Envelope>
```

## Key Components
- **Envelope**: Root, defines XML doc as SOAP
- **Header**: Optional, auth, transaction
- **Body**: Actual message/request/response
- **Fault**: Error handling
- **WSDL**: Web Services Description Language - contract (like OpenAPI for REST). Defines operations, types, endpoint.
- **UDDI**: Discovery (mostly obsolete)
- **XSD**: Types definition

## WSDL Example Structure
- Types: data types
- Message: request/response
- PortType: operations
- Binding: protocol
- Service: endpoint URL

## Characteristics
- Stateful or stateless (can be stateful)
- ACID compliant, with WS-* standards
- Built-in security: WS-Security (encryption, signing)
- Built-in retry, transaction: WS-ReliableMessaging, WS-AtomicTransaction
- Heavy, verbose

## When Use SOAP? (Interview)
- Enterprise, Banking, Payment gateways (old banks)
- Need strict contract, ACID, formal security
- Legacy systems
- When you need stateful operations

## SOAP vs REST Quick
| Feature | SOAP | REST |
|---------|------|------|
| Format | XML only | JSON/XML/HTML |
| Protocol | Protocol | Architectural style |
| Transport | HTTP/SMTP/TCP | HTTP only |
| Security | WS-Security high | HTTPS, OAuth |
| Performance | Heavy slow | Light fast |
| Caching | No | Yes |
| Learning | Hard | Easy |

## Tools
- SoapUI, Postman (supports SOAP)
- Code generation from WSDL: wsimport (Java), svcutil (.NET)

## Interview Tip
"SOAP still used in finance/telecom where WS-Security and transactions matter, but for new projects REST/GraphQL/gRPC preferred."
