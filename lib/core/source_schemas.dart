// GENERATED from the OpenAPI spec (IDataSource*). Field: key, required, kind (s=text, k=secret, b=bool).
class SrcField { const SrcField(this.key, this.required, this.kind); final String key; final bool required; final String kind; }
const kSourceSchemas = <String, List<SrcField>>{
  'alluxio': [SrcField('endpoint', true, 's'), SrcField('root', true, 's')],
  'azblob': [SrcField('container', true, 's'), SrcField('endpoint', true, 's'), SrcField('accountName', false, 's'), SrcField('accountKey', false, 'k'), SrcField('encryptionKey', false, 'k'), SrcField('encryptionKeySha256', false, 's'), SrcField('encryptionAlgorithm', false, 's'), SrcField('sasToken', false, 'k'), SrcField('skipSignature', false, 'b'), SrcField('root', true, 's')],
  'azdls': [SrcField('filesystem', true, 's'), SrcField('endpoint', true, 's'), SrcField('accountName', false, 's'), SrcField('accountKey', false, 'k'), SrcField('clientSecret', false, 'k'), SrcField('tenantId', false, 's'), SrcField('clientId', false, 's'), SrcField('sasToken', false, 'k'), SrcField('authorityHost', false, 's'), SrcField('enableHns', false, 'b'), SrcField('root', true, 's')],
  'azfile': [SrcField('endpoint', true, 's'), SrcField('shareName', true, 's'), SrcField('accountName', false, 's'), SrcField('accountKey', false, 'k'), SrcField('sasToken', false, 'k'), SrcField('root', true, 's')],
  'b2': [SrcField('applicationKeyId', true, 'k'), SrcField('applicationKey', true, 'k'), SrcField('bucket', true, 's'), SrcField('bucketId', true, 's'), SrcField('root', true, 's')],
  'cos': [SrcField('endpoint', true, 's'), SrcField('secretId', true, 'k'), SrcField('secretKey', true, 'k'), SrcField('securityToken', true, 'k'), SrcField('bucket', true, 's'), SrcField('root', true, 's')],
  'd1': [SrcField('token', true, 'k'), SrcField('accountId', true, 's'), SrcField('databaseId', true, 's'), SrcField('table', true, 's'), SrcField('keyField', true, 'k'), SrcField('valueField', true, 's'), SrcField('root', true, 's')],
  'dbfs': [SrcField('endpoint', true, 's'), SrcField('token', true, 'k'), SrcField('root', true, 's')],
  'dropbox': [SrcField('accessToken', true, 'k'), SrcField('refreshToken', true, 'k'), SrcField('clientId', true, 's'), SrcField('clientSecret', true, 'k'), SrcField('root', true, 's')],
  'ftp': [SrcField('endpoint', true, 's'), SrcField('user', true, 's'), SrcField('password', true, 'k'), SrcField('root', true, 's')],
  'gcs': [SrcField('bucket', true, 's'), SrcField('endpoint', false, 's'), SrcField('scope', false, 's'), SrcField('token', true, 'k'), SrcField('root', true, 's')],
  'gdrive': [SrcField('accessToken', true, 'k'), SrcField('refreshToken', true, 'k'), SrcField('clientId', true, 's'), SrcField('clientSecret', true, 'k'), SrcField('root', true, 's')],
  'fs': [SrcField('root', true, 's')],
  'onedrive': [SrcField('accessToken', true, 'k'), SrcField('refreshToken', true, 'k'), SrcField('clientId', true, 's'), SrcField('clientSecret', true, 'k'), SrcField('root', true, 's')],
  'pcloud': [SrcField('endpoint', true, 's'), SrcField('username', true, 's'), SrcField('password', true, 'k'), SrcField('root', true, 's')],
  's3': [SrcField('endpoint', false, 's'), SrcField('region', false, 's'), SrcField('accessKeyId', false, 'k'), SrcField('secretAccessKey', false, 'k'), SrcField('sessionToken', false, 'k'), SrcField('root', true, 's')],
  'webdav': [SrcField('endpoint', true, 's'), SrcField('username', true, 's'), SrcField('password', true, 'k'), SrcField('token', true, 'k'), SrcField('root', true, 's')],
};
