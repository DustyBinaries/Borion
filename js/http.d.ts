export interface BorionRequestInit extends RequestInit {
  /** Tempo máximo da requisição inteira, em ms (TIMEOUT ao estourar) */
  timeout?: number;
  /** Máximo de redirecionamentos seguidos (padrão 10; TOO_MANY_REDIRECTS acima) */
  maxRedirections?: number;
}

/**
 * fetch feito pelo Delphi (WinInet), sem CORS. Só URLs liberadas no Delphi
 * (Http.Allow); fora delas, rejeita com code 'FORBIDDEN_URL'. Outros codes:
 * INVALID_URL, TIMEOUT, CANCELED, TOO_MANY_REDIRECTS, TOO_LARGE, REDIRECT,
 * NETWORK_ERROR. Abortar pelo signal rejeita com AbortError.
 */
export declare function fetch(input: string | URL | Request, init?: BorionRequestInit): Promise<Response>;
