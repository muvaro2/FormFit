import pandas as pd
import numpy as np
import torch
import torch.nn as nn
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
from torch.utils.data import Dataset, DataLoader, random_split
from sklearn.preprocessing import StandardScaler


class ConvNet1D(nn.Module):
    def __init__(self):
        super().__init__()
        self.layer1 = nn.Sequential(
            nn.Conv1d(9, 64, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2), #reduces sample length by half
        
            nn.Conv1d(64, 128, kernel_size=3),
            nn.ReLU(),
            nn.Dropout(0.3),
            nn.MaxPool1d(2),
            
            nn.AdaptiveAvgPool1d(1)) #removes time by averaging
        self.layer2 = nn.Flatten()
        self.layer3 = nn.Sequential(
            nn.Linear(128, 32),
            nn.ReLU(),
            nn.Linear(32, 3), #classification into 3 metrics (elbow stability, scapular hiking, trunk compensation)
            nn.Sigmoid()) #classifies sample from 0-1 for each metric

    def forward(self, x):
        out = self.layer1(x)
        out = self.layer2(out)
        out = self.layer3(out)
        return out

class ExerciseDataset(Dataset):
    def __init__(self, x,y):
        self.x = torch.tensor(x,dtype=torch.float32) #number of samples
        self.y = torch.tensor(y,dtype=torch.float32) #output labels
    
    def __len__(self):
        return len(self.x)
    
    def __getitem__(self,i):
        return self.x[i],self.y[i]

def load_data(csv_path,seq_len=128):
    df = pd.read_csv(csv_path)

    sensor_cols = ['acc_x','acc_y','acc_z','gyro_x','gyro_y','gyro_z','roll','pitch','yaw']
    label_cols = ['elbow_stability','scapular_hiking','trunk_compensation']

    scaler = StandardScaler()
    df[sensor_cols] = scaler.fit_transform(df[sensor_cols])

    x,y = [],[]
    step = seq_len // 2
    for start in range(0,len(df) - seq_len, step):
        window = df[sensor_cols].iloc[start:start+seq_len].values
        x.append(window.T)
        y.append(df[label_cols].iloc[start].values)
    
    return np.array(x,dtype=np.float32), np.array(y, dtype=np.float32)

def build_loaders(x,y,batch_size=32,train_split=0.8):
    dataset = ExerciseDataset(x,y)

    train_size = int(train_split * len(dataset)) #number of samples in training set
    val_size = len(dataset) - train_size #number of samples in validation set

    train_ds, val_ds = random_split(dataset, [train_size,val_size]) #splits dataset
    
    train_loader = DataLoader(train_ds, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_ds, batch_size=batch_size)
    return train_loader, val_loader, dataset

#training loop function
def train(model, train_loader, val_loader, epochs=50):
    criterion = nn.BCELoss() #measures how wrong the predictions are
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3, weight_decay=1e-4) #updates the model's numbers after each run
    scheduler = torch.optim.lr_scheduler.ReduceLROnPlateau(
        optimizer, patience=5, factor=0.5
    ) #reduces learning rate if the model stalls

    history = {'train': [], 'val': []} #stores the loss so it can be graphed
    best_val_loss = float('inf')

    for epoch in range(epochs):
        #Trains the model
        model.train()
        train_loss = 0.0
        for X, y in train_loader:
            optimizer.zero_grad() #clears previous run's gradients

            #forward and backward passes over the data
            loss = criterion(model(X), y)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
            optimizer.step()
            train_loss += loss.item()

        #Validates the model
        model.eval()
        val_loss = 0.0
        with torch.no_grad():
            for X, y in val_loader:
                val_loss += criterion(model(X), y).item()

        avg_train = train_loss / len(train_loader) #average loss
        avg_val   = val_loss   / len(val_loader)
        history['train'].append(avg_train)
        history['val'].append(avg_val)
        scheduler.step(avg_val)

        # Saves the best model
        if avg_val < best_val_loss:
            best_val_loss = avg_val
            torch.save(model.state_dict(), 'best_model.pth')

        print(f"Epoch {epoch+1:3d} | Train: {avg_train:.4f} | Val: {avg_val:.4f}")

    return history

#gives feedback when the user is over the threshold
THRESHOLDS = {
    'elbow_stability': (0.5, "Elbow drifting"),
    'scapular_hiking': (0.5, "Shoulder shrugging"),
    'trunk_compensation': (0.5, "Trunk leaning"),
}

LENIENCY = 1.0 #Leniency factor - increase it to make grading easier

#function to add more leniency if the grading is too hard
def curve_cnn_score(raw_score, leniency=LENIENCY):
    return float(raw_score) ** (1.0/leniency)

#grades if the eccentric time is within the range
def eccentric_score(eccentric_time):
    if 2.0 <= eccentric_time <= 3.0:
        return 1.0
    return min(1.0, 1.25/(1+(eccentric_time - 2.5)**2))

def get_feedback(model, x_sample, eccentric_time, rom_deg, concentric_time, leniency=LENIENCY):
    model.eval() #turns off training behaviour and sets model to evaluation mode
    with torch.no_grad(): #stops PyTorch from tracking gradients
        x = torch.tensor(x_sample, dtype=torch.float32).unsqueeze(0) #converts x_sample to a tensor data structure
        preds = model(x).squeeze().numpy() #runs prediction model
    
    metric_names = ['elbow_stability', 'scapular_hiking','trunk_compensation']

    #converts outputs to likelihood %
    curved = [curve_cnn_score(p,leniency) for p in preds]
    likelihoods = [c*100 for c in curved]

    #25% weight for each metric
    metric_contributions = [(1.0 - c) * 25.0 for c in curved]

    ecc_score = eccentric_score(eccentric_time)
    ecc_contribution = ecc_score*25.0

    overall_score = sum(metric_contributions) + ecc_contribution

    metrics = []
    thresholds = {'elbow_stability': 50, 'scapular_hiking': 50, 'trunk_compensation':50}
    feedback_messages = {'elbow_stability': 'Elbow hiking detected', 'scapular_hiking': 'Scapular hiking detected', 'trunk_compensation': 'Torse twisting detected'}

    for name, likelihood, contribution in zip(metric_names, likelihoods, metric_contributions):
        flagged = likelihood > thresholds[name]
        metrics.append({
            'metric': name,
            'likelihood': round(likelihood,1),
            'contribution': round(contribution, 2),
            'flagged': flagged,
            'message': feedback_messages[name] if flagged else 'Good',
        })

    #loop through predictions
    return {
        'rom_deg': round(rom_deg,1),
        'concentric_time': round(concentric_time,2),
        'eccentric_time': round(eccentric_time,2),
        'eccentric_score': round(ecc_score*100,1),
        'eccentric_contribution': round(ecc_contribution,2),
        'metrics': metrics,
        'overall_score': round(overall_score,1),
    }

#print feedback function
def print_feedback(result):
    print("Form Feedback")
    print(f"ROM: {result['rom_deg']} (not scored)")
    print(f"Concentric Time: {result['concentric_time']}s")
    print(f"Eccentric Time: {result['eccentric_time']}s " f"{result['eccentric_score']}% ({result['eccentric_contribution']:.1f}/25 pts)")

    for item in result['metrics']:
        print(f"{item['metric']:20s} {item['likelihood']:5.1f}% ({item['contribution']:.1f}/25 pts) {item['message']}")

    print(f"\n Overall Score: {result['overall_score']}/100")

def plot_history(history):
    plt.figure(figsize=(8, 4))
    plt.plot(history['train'],label='Train Loss')
    plt.plot(history['val'],label='Val Loss')
    plt.xlabel('Epoch')
    plt.ylabel('BCE Loss')
    plt.title('Training History')
    plt.legend()
    plt.tight_layout()
    plt.show()

#evaluation function
def evaluate(model, val_loader): #takes in model and validation dataset
    model.eval()
    labels = ['elbow_stability', 'scapular_hiking','trunk_compensation']
    all_predictions = []
    all_labels = []

    with torch.no_grad(): #turns off gradient tracking
        for x,y in val_loader:
            preds = model(x)
            all_predictions.append((preds > 0.5).float())
            all_labels.append(y)
    
    #combines all predictions and labels
    all_predictions = torch.cat(all_predictions)
    all_labels = torch.cat(all_labels)

    print("\nValidation accuracy")
    for i,label in enumerate(labels):
        acc = (all_predictions[:,i] == all_labels[:,i]).float().mean().item()
        print(f"{label:25s}:{acc*100:.1f}%")

#makes test data
def make_test_csv(path, n_rows=500):
    df = pd.DataFrame(
        np.random.randn(n_rows,9),
        columns=['acc_x','acc_y','acc_z','gyro_x','gyro_y','gyro_z','roll','pitch','yaw']
    )
    df['elbow_stability'] = np.random.randint(0,2,n_rows)
    df['scapular_hiking'] = np.random.randint(0,2,n_rows)
    df['trunk_compensation'] = np.random.randint(0,2,n_rows)
    df.to_csv(path,index=False)

#exports model to CoreML
def export_coreml(model,seq_len=128,output_path="FormFitModel.mlpackage"):
    try:
        import coremltools as ct
    except ImportError:
        raise ImportError("Error Importing")
    
    model.eval()
    dummy = torch.zeros(1,9,seq_len)
    traced = torch.jit.trace(model,dummy)

    coreml_model = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input",shape=(1,9,seq_len))],
        outputs=[ct.TensorType(name="output")],
        minimum_deployment_target = ct.target.iOS16,
    )

    coreml_model.short_description = "Feedback: elbow stability, scapular hiking, trunk compensation"
    coreml_model.input_description = "9-channel sensors (acc xyz, gyro xyz, roll/pitch/yaw), shape(1,9,seq_len)"
    coreml_model.output_description = "3 scores for elbow stability, scapular hiking, trunk compensation"

    coreml_model.save(output_path)
    print(f"Export path: {output_path}")


if __name__ == "__main__":
    CSV_PATH = 'exercise_data.csv'
    SEQ_LEN = 128
    EPOCHS = 50

    make_test_csv(CSV_PATH)

    #load data
    x,y = load_data(CSV_PATH,seq_len = SEQ_LEN)
    train_loader,val_loader,dataset = build_loaders(x,y,batch_size=32)

    #Train model
    model = ConvNet1D()
    history = train(model,train_loader,val_loader,epochs=EPOCHS)
    plot_history(history)

    #Loads best model and evaluates
    model.load_state_dict(torch.load('best_model.pth'))
    evaluate(model,val_loader)

    #Obtain feedback
    sample_x, sample_y = dataset[len(dataset)-1]

    feedback = get_feedback(model, sample_x.numpy(), eccentric_time=2.4, rom_deg=45.0, concentric_time=1.1) #eccentric_time, rom_deg and concentric time values from calculate_metrics function
    print_feedback(feedback)

    #export to CoreML
    # export_coreml(model,seq_len=SEQ_LEN)