require 'openssl'
require 'acme-client'

require 'letsencrypt_webfaction/args_parser'
require 'letsencrypt_webfaction/domain_validator'
require 'letsencrypt_webfaction/certificate_installer'
require 'letsencrypt_webfaction/webfaction_api_credentials'

module LetsencryptWebfaction
  class Application
    def initialize(args)
      @options = LetsencryptWebfaction::ArgsParser.new(args)
    end

    def run!
      # Validate that the correct options were passed.
      validate_options!

      # Check credentials
      unless api_credentials.valid?
        $stderr.puts 'WebFaction API username, password, and/or servername are incorrect. Login failed.'
        exit 1
      end

      # Register the private key.
      register_key!

      # Validate the domains.
      return unless validator.validate!

      # Write the obtained certificates.
      certificate_installer.install!
    end

    private

    def api_credentials
      @_api_credentials ||= LetsencryptWebfaction::WebfactionApiCredentials.new username: @options.username, password: @options.password, servername: @options.servername, api_server: @options.api_url
    end

    def certificate_installer
      @certificate_installer ||= LetsencryptWebfaction::CertificateInstaller.new(@options.cert_name, certificate, api_credentials)
    end

    def certificate
      # We can now request a certificate, you can pass anything that returns
      # a valid DER encoded CSR when calling to_der on it, for example a
      # OpenSSL::X509::Request too.
      @certificate ||= client.new_certificate(csr)
    end

    def csr
      # We're going to need a certificate signing request. If not explicitly
      # specified, the first name listed becomes the common name.
      @csr ||= Acme::Client::CertificateRequest.new(names: @options.domains)
    end

    def validator
      @validator ||= LetsencryptWebfaction::DomainValidator.new @options.domains, client, @options.public
    end

    def client
      @client ||= Acme::Client.new(private_key: private_key, endpoint: @options.endpoint)
    end

    def register_key!
      # If the private key is not known to the server, we need to register it for the first time.
      registration = client.register(contact: "mailto:#{@options.letsencrypt_account_email}")

      # You'll may need to agree to the term (that's up the to the server to require it or not but boulder does by default)
      registration.agree_terms
    end

    def validate_options!
      return if @options.valid?
      raise ArgumentError, @options.errors.values.join("\n")
    end

    def private_key
      OpenSSL::PKey::RSA.new(@options.key_size)
    end
  end
end
