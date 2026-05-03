import React, { useState, useEffect } from 'react';
import { Download, Upload, ShieldCheck, X, File as FileIcon, Image as ImageIcon, Film, Music, FileText, Archive } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

type VaultFile = {
  name: string;
  ext: string;
  size: string;
};

function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  
  const [files, setFiles] = useState<VaultFile[]>([]);
  const [selectedFiles, setSelectedFiles] = useState<Set<string>>(new Set());
  const [previewFile, setPreviewFile] = useState<VaultFile | null>(null);
  const [isUploading, setIsUploading] = useState(false);

  useEffect(() => {
    if (isAuthenticated) {
      fetchFiles();
    }
  }, [isAuthenticated]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const res = await fetch(`/api/login?pin=${pin}`, { method: 'POST' });
      if (res.ok) {
        setIsAuthenticated(true);
        setError('');
      } else {
        setError('Incorrect PIN. Try again.');
      }
    } catch (err) {
      setError('Connection error.');
    }
  };

  const fetchFiles = async () => {
    try {
      const res = await fetch('/api/files');
      if (res.status === 401) {
        setIsAuthenticated(false);
        return;
      }
      const data = await res.json();
      setFiles(data);
    } catch (err) {
      console.error(err);
    }
  };

  const handleUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    if (!e.target.files || e.target.files.length === 0) return;
    setIsUploading(true);
    
    for (let i = 0; i < e.target.files.length; i++) {
      const formData = new FormData();
      formData.append('file', e.target.files[i]);
      await fetch('/api/upload', {
        method: 'POST',
        body: formData,
      });
    }
    
    setIsUploading(false);
    fetchFiles();
  };


  const downloadSelectedAsZip = () => {
    const form = document.createElement('form');
    form.method = 'POST';
    form.action = '/api/download_selected_zip';
    
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = 'files';
    input.value = Array.from(selectedFiles).join('|');
    
    form.appendChild(input);
    document.body.appendChild(form);
    form.submit();
    document.body.removeChild(form);
    setSelectedFiles(new Set());
  };

  const downloadAll = () => {
    window.location.href = '/api/download_all';
  };

  const getIcon = (ext: string) => {
    if (['jpg','jpeg','png','gif','webp'].includes(ext)) return <ImageIcon size={48} color="#60a5fa" />;
    if (['mp4','mov','mkv','avi'].includes(ext)) return <Film size={48} color="#f87171" />;
    if (['mp3','wav','m4a'].includes(ext)) return <Music size={48} color="#a78bfa" />;
    if (['pdf'].includes(ext)) return <FileText size={48} color="#fb923c" />;
    if (['zip','rar','tar','gz'].includes(ext)) return <Archive size={48} color="#fbbf24" />;
    return <FileIcon size={48} color="#94a3b8" />;
  };

  const canPreview = (ext: string) => {
    return ['jpg','jpeg','png','gif','webp','mp4','mov','mkv','avi','mp3','wav','m4a','pdf'].includes(ext);
  };

  const handleCardClick = (file: VaultFile) => {
    if (canPreview(file.ext)) {
      setPreviewFile(file);
    } else {
      window.location.href = `/api/download?path=${encodeURIComponent(file.name)}`;
    }
  };

  if (!isAuthenticated) {
    return (
      <div className="login-container">
        <motion.div 
          initial={{ scale: 0.9, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          className="glass-panel login-card"
        >
          <ShieldCheck size={48} color="#3b82f6" style={{ margin: '0 auto' }} />
          <h1>WiFi Vault</h1>
          <p style={{ color: 'var(--text-muted)' }}>Enter the 4-digit PIN shown on your phone to unlock.</p>
          <form onSubmit={handleLogin} style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <input 
              type="password" 
              maxLength={4} 
              className="pin-input" 
              value={pin}
              onChange={(e) => setPin(e.target.value.replace(/[^0-9]/g, ''))}
              placeholder="••••"
              autoFocus
            />
            {error && <div style={{ color: '#ef4444' }}>{error}</div>}
            <button type="submit" className="btn" style={{ justifyContent: 'center' }}>Unlock Vault</button>
          </form>
        </motion.div>
      </div>
    );
  }

  return (
    <div className="container">
      <header>
        <h1>WiFi Vault</h1>
        <div style={{ display: 'flex', gap: '12px' }}>
          <label className="btn btn-secondary">
            <Upload size={18} />
            Upload Files
            <input type="file" multiple onChange={handleUpload} style={{ display: 'none' }} />
          </label>
          <button className="btn btn-secondary" onClick={downloadAll}>
            <Download size={18} />
            Download All (ZIP)
          </button>
        </div>
      </header>

      <div className="file-grid">
        <AnimatePresence>
          {files.map((file) => (
            <motion.div
              layout
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.9 }}
              key={file.name}
              className={`glass-panel file-card ${selectedFiles.has(file.name) ? 'selected' : ''}`}
              onClick={() => handleCardClick(file)}
            >
              <div className="checkbox-wrapper" onClick={(e) => e.stopPropagation()}>
                <input 
                  type="checkbox" 
                  checked={selectedFiles.has(file.name)}
                  onChange={(e) => {
                    const newSet = new Set(selectedFiles);
                    if (e.target.checked) newSet.add(file.name);
                    else newSet.delete(file.name);
                    setSelectedFiles(newSet);
                  }}
                />
              </div>
              
              <div className="file-icon-container">
                {getIcon(file.ext)}
              </div>
              
              <div className="file-name" title={file.name}>{file.name}</div>
              
              <div className="file-meta">
                <span>{file.size}</span>
                <a 
                  href={`/api/download?path=${encodeURIComponent(file.name)}`} 
                  download={file.name}
                  onClick={(e) => e.stopPropagation()}
                  style={{ color: 'var(--accent)', textDecoration: 'none' }}
                >
                  Download
                </a>
              </div>
            </motion.div>
          ))}
        </AnimatePresence>
      </div>

      <AnimatePresence>
        {selectedFiles.size > 0 && (
          <motion.div 
            initial={{ y: 100, opacity: 0, x: '-50%' }}
            animate={{ y: 0, opacity: 1, x: '-50%' }}
            exit={{ y: 100, opacity: 0, x: '-50%' }}
            className="glass-panel fab-container"
          >
            <span style={{ alignSelf: 'center', fontWeight: 'bold' }}>{selectedFiles.size} selected</span>
            <button className="btn" onClick={downloadSelectedAsZip}>
              <Download size={18} /> Zip & Download
            </button>
            <button className="btn btn-secondary" onClick={() => setSelectedFiles(new Set())}>
              Clear
            </button>
          </motion.div>
        )}
      </AnimatePresence>

      <AnimatePresence>
        {previewFile && (
          <motion.div 
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="lightbox"
            onClick={() => setPreviewFile(null)}
          >
            <button className="lightbox-close" onClick={() => setPreviewFile(null)}>
              <X size={32} />
            </button>
            
            <div onClick={(e) => e.stopPropagation()} style={{ position: 'relative' }}>
              {['mp4','mov','mkv','avi'].includes(previewFile.ext) && (
                <video controls autoPlay className="lightbox-content" src={`/api/view?path=${encodeURIComponent(previewFile.name)}`} />
              )}
              {['mp3','wav','m4a'].includes(previewFile.ext) && (
                <audio controls autoPlay src={`/api/view?path=${encodeURIComponent(previewFile.name)}`} />
              )}
              {['pdf'].includes(previewFile.ext) && (
                <iframe className="lightbox-content" src={`/api/view?path=${encodeURIComponent(previewFile.name)}`} style={{ width: '80vw', height: '80vh', background: 'white' }} />
              )}
              {['jpg','jpeg','png','gif','webp'].includes(previewFile.ext) && (
                <img className="lightbox-content" src={`/api/view?path=${encodeURIComponent(previewFile.name)}`} alt="Preview" />
              )}
              <div style={{ color: 'white', marginTop: '16px', textAlign: 'center', fontSize: '18px' }}>
                {previewFile.name}
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>

      {isUploading && (
        <div className="overlay-loader">
          <div className="loader"></div>
          <div>Uploading... Please wait</div>
        </div>
      )}
    </div>
  );
}

export default App;
